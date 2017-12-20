import os

import click
import requests


def unwrap_vault_response(ca_file, vault_addr, wrap_info):
    response = requests.post(f'{vault_addr}/v1/sys/wrapping/unwrap',
                             headers={'X-Vault-Token': wrap_info['token']},
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
            token = unwrap_vault_response(ca_file, vault_addr, token.json()['wrap_info'])
            click.echo(f'fetched unwrapped token with accessor {token.json()["auth"]["accessor"]}')
    else:
        click.echo(f'fetched token with accessor {token.json()["auth"]["accessor"]}')
    return token.json()


@click.command()
@click.option('--namespace', default="default", help="namespace as defined by pod.metadata.namespace")
@click.option('--vault-kubernetes-auth-role', default=None, help="Vault Role to request for Kubernetes Auth.")
@click.option('--vault-kubernetes-auth-addr', default="https://vault-server.vault.svc.cluster.local", help="Vault Address to request for Kubernetes Auth.")
@click.option('--vault-kubernetes-auth-backend', default="auth/kubernetes/login", help="Path to attempt Vault Kubernetes Auth against")
@click.option('--vault-kubernetes-auth-token-path', default="/var/run/secrets/vault/", help="Directory to store vault-token file in", type=click.Path(exists=True))
@click.option('--wrap/--no-wrap', default=False, help="Use Vault Response Wrapping when requesting tokens, etc")
@click.option('--unwrap/--no-unwrap', default=False, help="Unwrap Vault Token response, may not be desirable for some apps")
def main(namespace, vault_kubernetes_auth_role, vault_kubernetes_auth_addr, vault_kubernetes_auth_backend, vault_kubernetes_auth_token_path, wrap, unwrap):
    click.echo(f'namespace: {namespace}')
    click.echo(f'vault_kubernetes_auth_role: {vault_kubernetes_auth_role}')
    click.echo(f'vault_kubernetes_auth_addr: {vault_kubernetes_auth_addr}')
    click.echo(f'vault_kubernetes_auth_backend: {vault_kubernetes_auth_backend}')
    click.echo(f'vault_kubernetes_auth_token_path: {vault_kubernetes_auth_token_path}')
    click.echo(f'wrap: {wrap}')
    click.echo(f'unwrap: {unwrap}')

    if vault_kubernetes_auth_role:
        click.echo(f'Attempting Vault Auth Login with Kubernetes for {namespace}-{vault_kubernetes_auth_role}')
        click.echo('reading jwt for vault kubernetes auth')
        with open('/var/run/secrets/kubernetes.io/serviceaccount/token', 'rU') as f:
            jwt = f.read()
        click.echo('fetching vault token')
        token = vault_kubernetes_auth_login(
            '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt',
            vault_kubernetes_auth_addr,
            vault_kubernetes_auth_backend,
            jwt,
            f'{namespace}-{vault_kubernetes_auth_role}',
            wrap,
            unwrap,
        )
        click.echo(token)
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

if __name__ == '__main__':
    main()
