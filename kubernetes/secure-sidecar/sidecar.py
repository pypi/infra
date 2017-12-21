import os
import time

import click
import requests


def wrapping_token_lookup(ca_file, vault_addr, token):
    response = requests.post(f'{vault_addr}/v1/sys/wrapping/lookup',
                             json={"token": token},
                             verify=ca_file)
    response.raise_for_status()
    return response


def token_lookup_self(ca_file, vault_addr, token):
    response = requests.get(f'{vault_addr}/v1/auth/token/lookup-self',
                            headers={'X-Vault-Token': token},
                            verify=ca_file)
    response.raise_for_status()
    return response


def token_renew_self(ca_file, vault_addr, token):
    response = requests.post(f'{vault_addr}/v1/auth/token/renew-self',
                             headers={'X-Vault-Token': token},
                             json={},
                             verify=ca_file)
    response.raise_for_status()
    return response


def unwrap_vault_response(ca_file, vault_addr, wrapping_token):
    response = requests.post(f'{vault_addr}/v1/sys/wrapping/unwrap',
                             headers={'X-Vault-Token': wrapping_token},
                             verify=ca_file)
    response.raise_for_status()
    return response


def vault_kubernetes_auth_login(ca_file, vault_addr, vault_backend, jwt, vault_role, wrap, unwrap):
    headers = {}
    if wrap:
        headers['X-Vault-Wrap-TTL'] = '60s'
    token = requests.post(f'{vault_addr}/v1/{vault_backend}',
                          headers=headers,
                          json={'jwt': jwt, 'role': vault_role},
                          verify=ca_file)
    token.raise_for_status()
    if wrap:
        click.echo(f'fetched wrapped token with accessor {token.json()["wrap_info"]["accessor"]}')
        if unwrap:
            click.echo(f'unwrapping accessor {token.json()["wrap_info"]["accessor"]}')
            token = unwrap_vault_response(ca_file, vault_addr, token.json()['wrap_info']['token'])
            click.echo(f'fetched unwrapped token with accessor {token.json()["auth"]["accessor"]}')
    else:
        click.echo(f'fetched token with accessor {token.json()["auth"]["accessor"]}')
    return token.json()


@click.group()
def cli():
    pass


@cli.command()
@click.option('--namespace', default="default", help="namespace as defined by pod.metadata.namespace")
@click.option('--vault-kubernetes-auth-role', default=None, help="Vault Role to request for Kubernetes Auth.")
@click.option('--vault-kubernetes-auth-addr', default="https://vault-server.vault.svc.cluster.local", help="Vault Address to request for Kubernetes Auth.")
@click.option('--vault-kubernetes-ca-file', default="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt", help="Certificate Authority to verify Vault TLS.")
@click.option('--vault-kubernetes-auth-backend', default="auth/kubernetes/login", help="Path to attempt Vault Kubernetes Auth against")
@click.option('--vault-kubernetes-auth-token-path', default="/var/run/secrets/vault/", help="Directory to store vault-token file in", type=click.Path(exists=True))
@click.option('--wrap/--no-wrap', default=False, help="Use Vault Response Wrapping when requesting tokens, etc")
@click.option('--unwrap/--no-unwrap', default=False, help="Unwrap Vault Token response, may not be desirable for some apps")
def kube_login(namespace, vault_kubernetes_auth_role, vault_kubernetes_auth_addr, vault_kubernetes_ca_file, vault_kubernetes_auth_backend, vault_kubernetes_auth_token_path, wrap, unwrap):
    if vault_kubernetes_auth_role:
        click.echo(f'Attempting Vault Auth Login with Kubernetes for {namespace}-{vault_kubernetes_auth_role}')
        click.echo('reading jwt for vault kubernetes auth')
        with open('/var/run/secrets/kubernetes.io/serviceaccount/token', 'rU') as f:
            jwt = f.read()
        click.echo('fetching vault token')
        token = vault_kubernetes_auth_login(
            vault_kubernetes_ca_file,
            vault_kubernetes_auth_addr,
            vault_kubernetes_auth_backend,
            jwt,
            f'{namespace}-{vault_kubernetes_auth_role}',
            wrap,
            unwrap,
        )
        if (wrap and unwrap) or not wrap:
            token_type = 'vault-token'
            token_path = os.path.join(vault_kubernetes_auth_token_path, 'vault-token')
            token_contents = token["auth"]["client_token"]
        else:
            token_type = 'wrapped-vault-token'
            token_path = os.path.join(vault_kubernetes_auth_token_path, 'wrapped-vault-token')
            token_contents = token["wrap_info"]["token"]
        click.echo(f'writing {token_type} to {token_path}')
        with open(token_path, 'w') as f:
            f.write(token_contents)


@cli.command()
@click.option('--vault-addr', default="https://vault-server.vault.svc.cluster.local", help="Vault address to communicate with.")
@click.option('--ca-file', default="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt", help="Certificate Authority to verify Vault TLS.")
@click.option('--token-file', default="/var/run/secrets/vault/vault-token", help="Path Vault Token is stored at", type=click.File(mode='rU'))
@click.option('--write-token-file', default="/var/run/secrets/vault/vault-token", help="Path Vault Token is stored at", type=click.File(mode='w'))
@click.option('--unwrap/--no-unwrap', default=False, help="Unwrap stored vault token, may not be desirable for some apps")
def fetch_and_renew(vault_addr, ca_file, token_file, write_token_file, unwrap):
    token = token_file.read()
    if unwrap:
        click.echo("Unwrapping from stored wrapped token")
        try:
            response = wrapping_token_lookup(ca_file, vault_addr, token)
            response.raise_for_status()
        except Exception as e:
            click.echo("Issue looking up wrapping token ID!: %s" % (e,))
            click.echo("Something may be amiss!")
            click.Abort()
        token = unwrap_vault_response(ca_file, vault_addr, token).json()["auth"]["client_token"]
        write_token_file.write(token)
        write_token_file.close()
    token_info = token_lookup_self(ca_file, vault_addr, token).json()
    click.echo(f'Using token with accessor {token_info["data"]["accessor"]} and policies {", ".join(token_info["data"]["policies"])}')

    while True:
        min_sleep = 60
        click.echo(f'checking vault token with accessor {token_info["data"]["accessor"]}')
        token_info = token_lookup_self(ca_file, vault_addr, token).json()
        if token_info['data']['renewable']:
            if token_info['data']['ttl'] < int(token_info['data']['creation_ttl']/2):
                click.echo(f'renewing vault token with accessor {token_info["data"]["accessor"]}')
                token_renew_self(ca_file, vault_addr, token)
                sleep = min_sleep
            else:
                sleep = max(min_sleep, int(token_info['data']['ttl']/4))
        click.echo(f'sleeping {sleep} seconds...')
        time.sleep(sleep)


if __name__ == '__main__':
    cli()
