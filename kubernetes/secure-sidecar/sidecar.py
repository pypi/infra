import contextlib
import datetime
import hashlib
import os
import pathlib
import time

import click
import iso8601
import requests

from cryptography import x509
from cryptography.hazmat.backends import default_backend


def wrapping_token_lookup(vault_ca_file, vault_addr, token):
    response = requests.post(f'{vault_addr}/v1/sys/wrapping/lookup',
                             json={"token": token},
                             verify=vault_ca_file)
    response.raise_for_status()
    return response


def unwrap_vault_response(vault_ca_file, vault_addr, wrapping_token):
    response = requests.post(f'{vault_addr}/v1/sys/wrapping/unwrap',
                             headers={'X-Vault-Token': wrapping_token},
                             verify=vault_ca_file)
    response.raise_for_status()
    return response


def token_lookup_self(vault_ca_file, vault_addr, token):
    response = requests.get(f'{vault_addr}/v1/auth/token/lookup-self',
                            headers={'X-Vault-Token': token},
                            verify=vault_ca_file)
    response.raise_for_status()
    return response


def token_renew_self(vault_ca_file, vault_addr, token):
    response = requests.post(f'{vault_addr}/v1/auth/token/renew-self',
                             headers={'X-Vault-Token': token},
                             json={},
                             verify=vault_ca_file)
    response.raise_for_status()
    return response


def token_revoke_self(vault_ca_file, vault_addr, token):
    response = requests.post(f'{vault_addr}/v1/auth/token/revoke-self',
                             headers={'X-Vault-Token': token},
                             json={},
                             verify=vault_ca_file)
    response.raise_for_status()
    return response


def leases_lookup(vault_ca_file, vault_addr, token, lease_id):
    response = requests.post(f'{vault_addr}/v1/sys/leases/lookup',
                             headers={'X-Vault-Token': token},
                             json={'lease_id': lease_id},
                             verify=vault_ca_file)
    response.raise_for_status()
    return response


def leases_renew(vault_ca_file, vault_addr, token, lease_id):
    response = requests.post(f'{vault_addr}/v1/sys/leases/renew',
                             headers={'X-Vault-Token': token},
                             json={'lease_id': lease_id},
                             verify=vault_ca_file)
    response.raise_for_status()
    return response


def vault_auth_kubernetes_login(vault_ca_file, vault_addr, vault_backend, vault_role, jwt, wrap, unwrap):
    headers = {}
    if wrap:
        headers['X-Vault-Wrap-TTL'] = '60s'
    token = requests.post(f'{vault_addr}/v1/{vault_backend}',
                          headers=headers,
                          json={'jwt': jwt, 'role': vault_role},
                          verify=vault_ca_file)
    token.raise_for_status()
    if wrap:
        click.echo(f'fetched wrapped token with accessor {token.json()["wrap_info"]["accessor"]}')
        if unwrap:
            click.echo(f'unwrapping accessor {token.json()["wrap_info"]["accessor"]}')
            token = unwrap_vault_response(vault_ca_file, vault_addr, token.json()['wrap_info']['token'])
            click.echo(f'fetched unwrapped token with accessor {token.json()["auth"]["accessor"]}')
    else:
        click.echo(f'fetched token with accessor {token.json()["auth"]["accessor"]}')
    return token.json()


@contextlib.contextmanager
def disposable_vault_token(vault_ca_file, vault_addr, vault_backend, vault_role, jwt):
    token = None
    try:
        click.echo(f"Requesting temporary vault token for role {vault_role}")
        token = vault_auth_kubernetes_login(vault_ca_file, vault_addr, vault_backend, vault_role, jwt, True, True)
        accessor = token['auth']['accessor']
        client_token = token['auth']['client_token']
        click.echo(f"Received temporary vault token with accessor {accessor}")
        yield client_token
    finally:
        token_revoke_self(vault_ca_file, vault_addr, client_token)
        click.echo(f"Succesfully revoked temporary token with accessor {accessor}")


def service_dns(service_name, namespace, domain):
    return [
        f'{service_name}.{namespace}.svc.{domain}',
        f'{service_name}.{namespace}.svc',
        f'{service_name}.{namespace}',
        f'{service_name}',
    ]


def pod_dns(pod_ip, namespace, domain):
    return [
        f'{pod_ip.replace(".", "-")}.{namespace}.pod.{domain}',
        f'{pod_ip.replace(".", "-")}.{namespace}.pod',
    ]


def headless_dns(hostname, subdomain, namespace, domain):
    return [
        f'{hostname}.{subdomain}.{namespace}.svc.{domain}',
        f'{hostname}.{subdomain}.{namespace}.svc',
        f'{hostname}.{subdomain}.{namespace}',
        f'{hostname}.{subdomain}',
        f'{hostname}',
    ]


def request_vault_certificate(vault_addr, vault_token, vault_ca_file, vault_pki_backend, vault_pki_role, common_name, alt_names, ip_sans):
    response = requests.post(f'{vault_addr}/v1/{vault_pki_backend}/issue/{vault_pki_role}',
                             json={"common_name": common_name, "alt_names": ','.join(alt_names), "ip_sans": ','.join(ip_sans)},
                             headers={'X-Vault-Token': vault_token},
                             verify=vault_ca_file)
    response.raise_for_status()
    click.echo(f'Obtained Private Key ({response.json()["data"].get("private_key_type")}) and Certificate with:')
    click.echo(f'  - Serial Number: {response.json()["data"].get("serial_number")}')
    click.echo(f'  - Vault Accessor: {response.json().get("accessor")}')
    click.echo(f'  - Vault Lease ID: {response.json().get("lease_id")}')
    click.echo(f'  - Vault Lease Duration: {response.json().get("lease_duration")}')
    return response


def write_key_material(cert_dir, cert_object):
    lease_id = cert_object.get('lease_id')
    private_key = cert_object['data'].get('private_key')
    certificate = cert_object['data'].get('certificate')
    issuing_ca = cert_object['data'].get('issuing_ca')
    lease_sha = hashlib.sha256(lease_id.encode('utf-8')).hexdigest()
    with open(os.path.join(cert_dir, 'leases', lease_sha), 'wb') as lease_file:
        lease_file.write(lease_id.encode('utf-8'))
    with open(os.path.join(cert_dir, 'key.pem'), 'wb') as key_file:
        key_file.write(private_key.encode('utf-8'))
        key_file.write(b'\n')
    with open(os.path.join(cert_dir, 'cert.pem'), 'wb') as cert_file:
        cert_file.write(certificate.encode('utf-8'))
        cert_file.write(b'\n')
    with open(os.path.join(cert_dir, 'ca.pem'), 'wb') as ca_file:
        ca_file.write(issuing_ca.encode('utf-8'))
        ca_file.write(b'\n')
    with open(os.path.join(cert_dir, 'chain.pem'), 'wb') as chain_file:
        chain_file.write(certificate.encode('utf-8'))
        chain_file.write(b'\n')
        chain_file.write(issuing_ca.encode('utf-8'))
        chain_file.write(b'\n')
    click.echo(f'Wrote Key Material to {os.path.join(cert_dir, "{cert.pem, key.pem, ca.pem, chain.pem}")}')


def certificate_needs_renewed(cert_dir):
    with open(os.path.join(cert_dir, 'cert.pem'), 'rb') as cert_file:
        pem_data = cert_file.read()
    cert = x509.load_pem_x509_certificate(pem_data, default_backend())
    not_valid_after = cert.not_valid_after
    return not_valid_after - datetime.datetime.utcnow() < datetime.timedelta(hours=12)


def read_cert(cert_dir):
    with open(os.path.join(cert_dir, 'cert.pem'), 'rb') as cert_file:
        pem_data = cert_file.read()
    cert = x509.load_pem_x509_certificate(pem_data, default_backend())
    common_name = [na.value for na in cert.subject if na.oid._dotted_string == "2.5.4.3"][0]
    subject_alternative_names = [ext.value for ext in cert.extensions if ext.oid._dotted_string == "2.5.29.17"][0]
    dns_names = subject_alternative_names.get_values_for_type(x509.DNSName)
    ip_sans = [str(ip) for ip in subject_alternative_names.get_values_for_type(x509.IPAddress)]

    return common_name, dns_names, ip_sans


def vault_fetch_certificate(vault_addr, vault_token, vault_ca_file, vault_pki_backend, vault_pki_role, cert_dir,
                            from_cert=False, hostname=None, subdomain=None, namespace=None, cluster_domain=None,
                            pod_name=None, pod_ip=None, additional_dns_names=None, service_names=None, service_ips=None):
    if from_cert:
        common_name, dns_names, ip_sans = read_cert(cert_dir)
    else:
        dns_names = pod_dns(pod_ip, namespace, cluster_domain)
        dns_names += [x for x in additional_dns_names.split(',') if x]
        for service_name in service_names.split(','):
            if service_name:
                dns_names += service_dns(service_name, namespace, cluster_domain)

        if hostname and subdomain:
            dns_names += headless_dns(hostname, subdomain, namespace, cluster_domain)

        ip_sans = [pod_ip]
        ip_sans += [x for x in service_ips.split(',') if x]

        common_name = dns_names[0]

    certificate_response = request_vault_certificate(vault_addr, vault_token, vault_ca_file, vault_pki_backend, vault_pki_role, common_name, dns_names, ip_sans)
    write_key_material(cert_dir, certificate_response.json())


def request_consul_token(vault_addr, token, vault_ca_file, consul_backend, consul_role):
    response = requests.get(f'{vault_addr}/v1/{consul_backend}/creds/{consul_role}',
                            headers={'X-Vault-Token': token},
                            verify=vault_ca_file)
    response.raise_for_status()
    click.echo('Obtained Consul Token with:')
    click.echo(f'  - Vault Lease ID: {response.json().get("lease_id")}')
    click.echo(f'  - Vault Lease Duration: {response.json().get("lease_duration")}')
    return response


def write_consul_token(consul_secrets_path, consul_token_object):
    lease_id = consul_token_object['lease_id']
    token = consul_token_object['data']['token']
    lease_sha = hashlib.sha256(lease_id.encode('utf-8')).hexdigest()
    with open(os.path.join(consul_secrets_path, 'leases', lease_sha), 'wb') as lease_file:
        lease_file.write(lease_id.encode('utf-8'))
    with open(os.path.join(consul_secrets_path, 'consul-token'), 'wb') as token_file:
        token_file.write(token.encode('utf-8'))
    click.echo(f'Wrote Consul Token to {os.path.join(consul_secrets_path, "consul-token")}')


def vault_fetch_consul_token(vault_addr, token_contents, vault_ca_file, vault_consul_backend, vault_consul_role, consul_secrets_path):
    consul_token_response = request_consul_token(vault_addr, token_contents, vault_ca_file, vault_consul_backend, vault_consul_role)
    write_consul_token(consul_secrets_path, consul_token_response.json())


@click.group()
def cli():
    pass


@cli.command()
@click.option('--namespace', default="default", help="namespace as defined by pod.metadata.namespace")
@click.option('--vault-addr', default="https://vault-server.vault.svc.cluster.local", help="Vault Address to request for Kubernetes Auth.")
@click.option('--vault-ca-file', default="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt", help="Certificate Authority to verify Vault TLS.")
@click.option('--vault-secrets-path', default="/var/run/secrets/vault/", help="Directory to store secrets in", type=click.Path(exists=True, file_okay=False, writable=True))
@click.option('--vault-auth-kubernetes-role', default=None, help="Vault Role to request for Kubernetes Auth.")
@click.option('--vault-auth-kubernetes-backend', default="auth/kubernetes/login", help="Path to attempt Vault Kubernetes Auth against")
@click.option('--fetch-consul-token/--no-fetch-consul-token', default=False, help="Fetch a Consul Token from a Vault Consul Secret Backend")
@click.option('--consul-secrets-path', default="/var/run/secrets/vault/", help="Directory to store consul token in", type=click.Path(exists=True, file_okay=False, writable=True))
@click.option('--vault-consul-role', default=None, help="Vault Role to request for Kubernetes Auth.")
@click.option('--vault-consul-backend', default="cabotage-consul", help="Path to fetch Consul creds from")
@click.option('--fetch-cert/--no-fetch-cert', default=False, help="Fetch a TLS Certificate from the Vault CA")
@click.option('--cert-dir', default="/var/run/secrets/vault", help="directory to store tls key and cert", type=click.Path(exists=True, file_okay=False, writable=True))
@click.option('--vault-pki-backend', default="cabotage-ca", help="Vault PKI backend to request certificate from.")
@click.option('--vault-pki-role', help="Vault PKI role to request certificate from.")
@click.option('--hostname', default="", help="hostname as defined by pod.spec.hostname")
@click.option('--subdomain', default="", help="subdomain as defined by pod.spec.subdomain")
@click.option('--cluster-domain', default="cluster.local", help="kubernetes cluster domain")
@click.option('--pod-name', help="name as defined by pod.metadata.name")
@click.option('--pod-ip', help="pod IP address as defined by pod.status.podIP")
@click.option('--additional-dns_names', default="", help="additional dns names; comma separated")
@click.option('--service-names', default="", help="service names that resolve to this Pod; comma separated")
@click.option('--service-ips', default="", help="service IP addresses that resolve to this Pod; comma separated")
@click.option('--wrap/--no-wrap', default=True, help="Use Vault Response Wrapping when requesting tokens, etc")
@click.option('--unwrap/--no-unwrap', default=True, help="Unwrap Vault responses, may not be desirable for some apps")
def kube_login(namespace, vault_addr, vault_ca_file, vault_secrets_path,
               vault_auth_kubernetes_role, vault_auth_kubernetes_backend,
               fetch_consul_token, consul_secrets_path, vault_consul_role, vault_consul_backend,
               fetch_cert, cert_dir, vault_pki_backend, vault_pki_role,
               hostname, subdomain, cluster_domain,
               pod_name, pod_ip, additional_dns_names, service_names, service_ips,
               wrap, unwrap):
    if fetch_consul_token:
        if vault_consul_role is None:
            raise click.BadParameter('--vault-consul-role is required when fetching consul token')
    if fetch_cert:
        if vault_pki_role is None:
            raise click.BadParameter('--vault-pki-role is required when fetching TLS certificate')
        if pod_ip is None:
            raise click.BadParameter('--pod-ip is required when fetching TLS certificate')

    if (fetch_cert or fetch_consul_token) and not unwrap:
        raise click.BadParameter('--no-unwrap cannot be used with --fetch-consul-token or --fetch-cert!\n'
                                 '                        unwrapped token must be accessible during bootstrap')

    os.makedirs(os.path.join(vault_secrets_path, 'leases'), exist_ok=True)
    with open('/var/run/secrets/kubernetes.io/serviceaccount/token', 'rU') as token_file:
        jwt = token_file.read()

    if vault_auth_kubernetes_role:
        click.echo(f'Attempting Vault Auth Login with Kubernetes for {namespace}-{vault_auth_kubernetes_role}')
        click.echo('reading jwt for vault kubernetes auth')
        click.echo('fetching vault token')
        token = vault_auth_kubernetes_login(vault_ca_file, vault_addr,
                                            vault_auth_kubernetes_backend, vault_auth_kubernetes_role,
                                            jwt, wrap, unwrap)
        if (wrap and unwrap) or not wrap:
            token_type = 'vault-token'
            token_path = os.path.join(vault_secrets_path, 'vault-token')
            token_contents = token["auth"]["client_token"]
        else:
            token_type = 'wrapped-vault-token'
            token_path = os.path.join(vault_secrets_path, 'wrapped-vault-token')
            token_contents = token["wrap_info"]["token"]
        click.echo(f'writing {token_type} to {token_path}')
        with open(token_path, 'w') as vault_token_file:
            vault_token_file.write(token_contents)

    if fetch_consul_token:
        os.makedirs(os.path.join(consul_secrets_path, 'leases'), exist_ok=True)
        vault_fetch_consul_token(vault_addr, token_contents, vault_ca_file, vault_consul_backend, vault_consul_role, consul_secrets_path)
    if fetch_cert:
        os.makedirs(os.path.join(cert_dir, 'leases'), exist_ok=True)
        vault_fetch_certificate(vault_addr, token_contents, vault_ca_file, vault_pki_backend, vault_pki_role, cert_dir,
                                from_cert=False, hostname=hostname, subdomain=subdomain, namespace=namespace, cluster_domain=cluster_domain,
                                pod_name=pod_name, pod_ip=pod_ip, additional_dns_names=additional_dns_names,
                                service_names=service_names, service_ips=service_ips)


@cli.command()
@click.option('--vault-addr', default="https://vault-server.vault.svc.cluster.local", help="Vault address to communicate with.")
@click.option('--vault-ca-file', default="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt", help="Certificate Authority to verify Vault TLS.")
@click.option('--vault-secrets-path', default="/var/run/secrets/vault/", help="Directory to store secrets in", type=click.Path(exists=True, file_okay=False, writable=True))
@click.option('--vault-token-file', default="/var/run/secrets/vault/vault-token", help="Path Vault Token is stored at", type=click.File(mode='rU'))
@click.option('--consul-secrets-path', default="/var/run/secrets/vault/", help="Directory to store consul token in", type=click.Path(exists=True, file_okay=False, writable=True))
@click.option('--cert-dir', default="/var/run/secrets/vault", help="Path Vault Issued Certificate and Key are stored at", type=click.Path())
@click.option('--vault-pki-backend', default="cabotage-ca", help="Vault PKI backend to request certificate from.")
@click.option('--vault-pki-role', help="Vault PKI role to request certificate from.")
@click.option('--unwrap/--no-unwrap', default=False, help="Unwrap stored vault token, may not be desirable for some apps")
@click.option('--write-vault-token-file', default="/var/run/secrets/vault/vault-token", help="File to write unrwapped Vault Token to", type=click.File(mode='w'))
def maintain(vault_addr, vault_ca_file, vault_secrets_path, vault_token_file,
             consul_secrets_path, cert_dir, vault_pki_backend, vault_pki_role,
             unwrap, write_vault_token_file):
    vault_token = vault_token_file.read()
    if unwrap:
        click.echo("Unwrapping from stored wrapped token")
        try:
            response = wrapping_token_lookup(vault_ca_file, vault_addr, vault_token)
            response.raise_for_status()
        except Exception as exc:
            click.echo("Issue looking up wrapping token ID!: %s" % (exc,))
            click.echo("Something may be amiss!")
            click.Abort()
        vault_token = unwrap_vault_response(vault_ca_file, vault_addr, token).json()["auth"]["client_token"]
        write_vault_token_file.write(vault_token)
        write_vault_token_file.close()
        vault_token_file.close()
        os.remove(vault_token_file.name)
    vault_token_info = token_lookup_self(vault_ca_file, vault_addr, vault_token).json()
    click.echo(f'Using token with accessor {vault_token_info["data"]["accessor"]} and policies {", ".join(vault_token_info["data"]["policies"])}')

    while True:
        min_sleep = 60
        click.echo(f'checking vault token with accessor {vault_token_info["data"]["accessor"]}')
        vault_token_info = token_lookup_self(vault_ca_file, vault_addr, vault_token).json()
        if vault_token_info['data']['renewable']:
            if vault_token_info['data']['ttl'] < int(vault_token_info['data']['creation_ttl']/2):
                click.echo(f'renewing vault token with accessor {vault_token_info["data"]["accessor"]}')
                token_renew_self(vault_ca_file, vault_addr, vault_token)
                sleep = min_sleep
            else:
                sleep = max(min_sleep, int(vault_token_info['data']['ttl']/4))
        for lease_dir in set([os.path.join(x, 'leases') for x  in [vault_secrets_path, consul_secrets_path, cert_dir]]):
            click.echo(f'Checking expiry of leases in {lease_dir}...')
            for lease_file in os.listdir(lease_dir):
                click.echo(f'Checking expiry of lease: {lease_file}...')
                with open(os.path.join(lease_dir, lease_file), 'rU') as f:
                    lease_id = f.read()
                lease_info = leases_lookup(vault_ca_file, vault_addr, vault_token, lease_id).json()['data']
                if lease_info['ttl'] > 0:
                    initial_ttl = iso8601.parse_date(lease_info['expire_time']) - iso8601.parse_date(lease_info['issue_time'])
                    if lease_info['ttl'] < int(initial_ttl.total_seconds() / 2):
                        click.echo(f'Renewing lease {lease_info["id"]}...')
                        new_lease = leases_renew(vault_ca_file, vault_addr, vault_token, lease_id).json()
                        click.echo(f'Renewed lease {new_lease["lease_id"]} for {new_lease["lease_duration"]}s!')
                        lease_sha = hashlib.sha256(new_lease["lease_id"].encode('utf-8')).hexdigest()
                        if lease_sha != lease_file:
                            os.remove(os.path.join(lease_dir, lease_file))
                            with open(os.path.join(lease_dir, lease_sha), 'wb') as lease_file:
                                lease_file.write(new_lease["lease_id"].encode('utf-8'))
                        else:
                            pathlib.Path(os.path.join(lease_dir, lease_file)).touch()
                else:
                    click.echo('Removing expired lease file for {lease_info["id"]}')
                    os.remove(os.path.join(lease_dir, lease_file))
        if os.path.exists(os.path.join(cert_dir, 'cert.pem')):
            if certificate_needs_renewed(cert_dir):
                fetch_certificate(vault_addr, vault_token, vault_ca_file, vault_pki_backend, vault_pki_role, cert_dir)
        click.echo(f'sleeping {sleep} seconds...')
        time.sleep(sleep)


if __name__ == '__main__':
    cli()
