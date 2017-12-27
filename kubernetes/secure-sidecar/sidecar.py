import datetime
import os
import time

import click
import requests

from cryptography import x509
from cryptography.hazmat.backends import default_backend


def wrapping_token_lookup(vault_ca_file, vault_addr, token):
    response = requests.post(f'{vault_addr}/v1/sys/wrapping/lookup',
                             json={"token": token},
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


def unwrap_vault_response(vault_ca_file, vault_addr, wrapping_token):
    response = requests.post(f'{vault_addr}/v1/sys/wrapping/unwrap',
                             headers={'X-Vault-Token': wrapping_token},
                             verify=vault_ca_file)
    response.raise_for_status()
    return response


def vault_kubernetes_auth_login(vault_ca_file, vault_addr, vault_backend, jwt, vault_role, wrap, unwrap):
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
    return response


def write_key_material(cert_dir, private_key, certificate, issuing_ca):
    with open(os.path.join(cert_dir, 'key.pem'), 'wb') as f:
        f.write(private_key.encode('utf-8'))
        f.write(b'\n')
    with open(os.path.join(cert_dir, 'cert.pem'), 'wb') as f:
        f.write(certificate.encode('utf-8'))
        f.write(b'\n')
    with open(os.path.join(cert_dir, 'ca.pem'), 'wb') as f:
        f.write(issuing_ca.encode('utf-8'))
        f.write(b'\n')
    with open(os.path.join(cert_dir, 'chain.pem'), 'wb') as f:
        f.write(certificate.encode('utf-8'))
        f.write(b'\n')
        f.write(issuing_ca.encode('utf-8'))
        f.write(b'\n')


def certificate_needs_renewed(cert_dir):
    with open(os.path.join(cert_dir, 'cert.pem'), 'rb') as f:
        pem_data = f.read()
    cert = x509.load_pem_x509_certificate(pem_data, default_backend())
    not_valid_after = cert.not_valid_after
    return not_valid_after - datetime.datetime.utcnow() < datetime.timedelta(hours=12)


def renew_certificate(vault_addr, vault_token, vault_ca_file, vault_pki_backend, vault_pki_role, cert_dir):
    with open(os.path.join(cert_dir, 'cert.pem'), 'rb') as f:
        pem_data = f.read()
    cert = x509.load_pem_x509_certificate(pem_data, default_backend())
    common_name = [na.value for na in cert.subject if na.oid._dotted_string == "2.5.4.3"][0]
    subject_alternative_names = [ext.value for ext in cert.extensions if ext.oid._dotted_string == "2.5.29.17"][0]
    dns_names = subject_alternative_names.get_values_for_type(x509.DNSName)
    ip_sans = [str(ip) for ip in subject_alternative_names.get_values_for_type(x509.IPAddress)]

    certificate_response = request_vault_certificate(vault_addr, vault_token, vault_ca_file, vault_pki_backend, vault_pki_role, common_name, dns_names, ip_sans)
    cert_object = certificate_response.json()

    click.echo(f'Obtained Private Key ({cert_object["data"].get("private_key_type")}) and Certificate with:')
    click.echo(f'  - Serial Number: {cert_object["data"].get("serial_number")}')
    click.echo(f'  - Vault Lease ID: {cert_object.get("lease_id")}')
    click.echo(f'  - Vault Lease Duration: {cert_object.get("lease_duration")}')

    private_key = cert_object['data'].get('private_key')
    certificate = cert_object['data'].get('certificate')
    issuing_ca = cert_object['data'].get('issuing_ca')
    write_key_material(cert_dir, private_key, certificate, issuing_ca)
    click.echo(f'Wrote Key Material to {os.path.join(cert_dir, "{cert.pem, key.pem, ca.pem, chain.pem}")}')


@click.group()
def cli():
    pass


@cli.command()
@click.option('--namespace', default="default", help="namespace as defined by pod.metadata.namespace")
@click.option('--vault-addr', default="https://vault-server.vault.svc.cluster.local", help="Vault Address to request for Kubernetes Auth.")
@click.option('--vault-ca-file', default="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt", help="Certificate Authority to verify Vault TLS.")
@click.option('--vault-kubernetes-auth-role', default=None, help="Vault Role to request for Kubernetes Auth.")
@click.option('--vault-kubernetes-auth-backend', default="auth/kubernetes/login", help="Path to attempt Vault Kubernetes Auth against")
@click.option('--vault-kubernetes-auth-token-path', default="/var/run/secrets/vault/", help="Directory to store vault-token file in", type=click.Path(exists=True))
@click.option('--wrap/--no-wrap', default=False, help="Use Vault Response Wrapping when requesting tokens, etc")
@click.option('--unwrap/--no-unwrap', default=False, help="Unwrap Vault responses, may not be desirable for some apps")
def kube_login(namespace, vault_addr, vault_ca_file, vault_kubernetes_auth_role, vault_kubernetes_auth_backend, vault_kubernetes_auth_token_path, wrap, unwrap):
    if vault_kubernetes_auth_role:
        click.echo(f'Attempting Vault Auth Login with Kubernetes for {namespace}-{vault_kubernetes_auth_role}')
        click.echo('reading jwt for vault kubernetes auth')
        with open('/var/run/secrets/kubernetes.io/serviceaccount/token', 'rU') as f:
            jwt = f.read()
        click.echo('fetching vault token')
        token = vault_kubernetes_auth_login(
            vault_ca_file,
            vault_addr,
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
@click.option('--vault-ca-file', default="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt", help="Certificate Authority to verify Vault TLS.")
@click.option('--vault-pki-backend', default="cabotage-ca", help="Vault PKI backend to request certificate from.")
@click.option('--vault-pki-role', required=True, help="Vault PKI role to request certificate from.")
@click.option('--token-file', default="/var/run/secrets/vault/vault-token", help="Path Vault Token is stored at", type=click.File(mode='rU'))
@click.option('--cert-dir', default="/etc/tls", help="directory to store tls key and cert", type=click.Path(exists=True))
@click.option('--hostname', default="", help="hostname as defined by pod.spec.hostname")
@click.option('--subdomain', default="", help="subdomain as defined by pod.spec.subdomain")
@click.option('--namespace', default="default", help="namespace as defined by pod.metadata.namespace")
@click.option('--cluster-domain', default="cluster.local", help="kubernetes cluster domain")
@click.option('--pod-name', required=True, help="name as defined by pod.metadata.name")
@click.option('--pod-ip', required=True, help="pod IP address as defined by pod.status.podIP")
@click.option('--additional-dnsnames', default="", help="additional dns names; comma separated")
@click.option('--service-names', default="", help="service names that resolve to this Pod; comma separated")
@click.option('--service-ips', default="", help="service IP addresses that resolve to this Pod; comma separated")
def fetch_vault_cert(vault_addr, vault_ca_file, vault_pki_backend, vault_pki_role, token_file, cert_dir,
                     hostname, subdomain, namespace, cluster_domain,
                     pod_name, pod_ip, additional_dnsnames, service_names, service_ips):
    dnsnames = pod_dns(pod_ip, namespace, cluster_domain)
    dnsnames += [x for x in additional_dnsnames.split(',') if x]
    for service_name in service_names.split(','):
        if service_name:
            dnsnames += service_dns(service_name, namespace, cluster_domain)

    if hostname and subdomain:
        dnsnames += headless_dns(hostname, subdomain, namespace, cluster_domain)

    ips = [pod_ip]
    ips += [x for x in service_ips.split(',') if x]

    common_name = dnsnames[0]

    certificate_response = request_vault_certificate(vault_addr, token_file.read(), vault_ca_file, vault_pki_backend, vault_pki_role, common_name, set(dnsnames), set(ips))
    cert_object = certificate_response.json()

    click.echo(f'Obtained Private Key ({cert_object["data"].get("private_key_type")}) and Certificate with:')
    click.echo(f'  - Serial Number: {cert_object["data"].get("serial_number")}')
    click.echo(f'  - Vault Lease ID: {cert_object.get("lease_id")}')
    click.echo(f'  - Vault Lease Duration: {cert_object.get("lease_duration")}')

    private_key = cert_object['data'].get('private_key')
    certificate = cert_object['data'].get('certificate')
    issuing_ca = cert_object['data'].get('issuing_ca')
    write_key_material(cert_dir, private_key, certificate, issuing_ca)
    click.echo(f'Wrote Key Material to {os.path.join(cert_dir, "{cert.pem, key.pem, ca.pem, chain.pem}")}')


@cli.command()
@click.option('--vault-addr', default="https://vault-server.vault.svc.cluster.local", help="Vault address to communicate with.")
@click.option('--vault-ca-file', default="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt", help="Certificate Authority to verify Vault TLS.")
@click.option('--token-file', default="/var/run/secrets/vault/vault-token", help="Path Vault Token is stored at", type=click.File(mode='rU'))
@click.option('--cert-dir', default="/etc/tls", help="Path Vault Issued Certificate and Key are stored at", type=click.Path())
@click.option('--write-token-file', default="/var/run/secrets/vault/vault-token", help="Path Vault Token is stored at", type=click.File(mode='w'))
@click.option('--unwrap/--no-unwrap', default=False, help="Unwrap stored vault token, may not be desirable for some apps")
@click.option('--vault-pki-backend', default="cabotage-ca", help="Vault PKI backend to request certificate from.")
@click.option('--vault-pki-role', help="Vault PKI role to request certificate from.")
def fetch_and_renew(vault_addr, vault_ca_file, token_file, cert_dir, write_token_file, unwrap, vault_pki_backend, vault_pki_role):
    token = token_file.read()
    if unwrap:
        click.echo("Unwrapping from stored wrapped token")
        try:
            response = wrapping_token_lookup(vault_ca_file, vault_addr, token)
            response.raise_for_status()
        except Exception as e:
            click.echo("Issue looking up wrapping token ID!: %s" % (e,))
            click.echo("Something may be amiss!")
            click.Abort()
        token = unwrap_vault_response(vault_ca_file, vault_addr, token).json()["auth"]["client_token"]
        write_token_file.write(token)
        write_token_file.close()
        token_file.close()
        os.remove(token_file.name)
    token_info = token_lookup_self(vault_ca_file, vault_addr, token).json()
    click.echo(f'Using token with accessor {token_info["data"]["accessor"]} and policies {", ".join(token_info["data"]["policies"])}')

    while True:
        min_sleep = 60
        click.echo(f'checking vault token with accessor {token_info["data"]["accessor"]}')
        token_info = token_lookup_self(vault_ca_file, vault_addr, token).json()
        if token_info['data']['renewable']:
            if token_info['data']['ttl'] < int(token_info['data']['creation_ttl']/2):
                click.echo(f'renewing vault token with accessor {token_info["data"]["accessor"]}')
                token_renew_self(vault_ca_file, vault_addr, token)
                sleep = min_sleep
            else:
                sleep = max(min_sleep, int(token_info['data']['ttl']/4))
        if os.path.exists(os.path.join(cert_dir, 'cert.pem')):
            if certificate_needs_renewed(cert_dir):
                renew_certificate(vault_addr, token, vault_ca_file, vault_pki_backend, vault_pki_role, cert_dir)
        click.echo(f'sleeping {sleep} seconds...')
        time.sleep(sleep)


if __name__ == '__main__':
    cli()
