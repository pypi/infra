import base64
import os
import time

from ipaddress import ip_address

import kubernetes
from kubernetes.client.rest import ApiException

import click

from cryptography import x509
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID


def generate_csr(common_name, dnsnames, ips, keysize):
    key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=keysize,
        backend=default_backend()
    )

    key_pem = key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.TraditionalOpenSSL,
        encryption_algorithm=serialization.NoEncryption(),
    )

    csr = x509.CertificateSigningRequestBuilder()
    csr = csr.subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, common_name)]))
    csr = csr.add_extension(
        x509.SubjectAlternativeName(dnsnames + ips),
        critical=False,
    )
    csr = csr.sign(key, hashes.SHA256(), default_backend())

    csr_pem = csr.public_bytes(serialization.Encoding.PEM)

    return key_pem, csr_pem


def service_dns(service_name, namespace, domain):
    return x509.DNSName(f'{service_name}.{namespace}.svc.{domain}')


def pod_dns(pod_ip, namespace, domain):
    return x509.DNSName(f'{pod_ip.replace(".", "-")}.{namespace}.pod.{domain}')


def headless_dns(hostname, subdomain, namespace, domain):
    return x509.DNSName(f'{hostname}.{subdomain}.{namespace}.svc.{domain}')


@click.command()
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
@click.option('--keysize', default=2048, help="size of private key; bits")
def main(cert_dir, hostname, subdomain, namespace, cluster_domain, pod_name, pod_ip, additional_dnsnames, service_names, service_ips, keysize):
    csr_name = f'{namespace}-{pod_name}-{int(time.time())}'

    dnsnames = [pod_dns(pod_ip, namespace, cluster_domain)]
    dnsnames += [x509.DNSName(x) for x in additional_dnsnames.split(',') if x]
    dnsnames += [service_dns(x, namespace, cluster_domain) for x in service_names.split(',') if x]

    if hostname and subdomain:
        dnsnames += [headless_dns(hostname, subdomain, namespace, cluster_domain)]

    ips = [x509.IPAddress(ip_address(pod_ip))]
    ips += [x509.IPAddress(ip_address(x)) for x in service_ips.split(',') if x]

    common_name = dnsnames[0]._value
    key_pem, csr_pem = generate_csr(common_name, dnsnames, ips, keysize)
    click.echo('Generated Key')
    click.echo('Generated CSR for:')
    click.echo('DNSNames:\n%s' % ("\n".join([" - " + str(d) for d in dnsnames])))
    click.echo('IPs:\n%s' % ("\n".join([" - " + str(i) for i in ips])))

    with open(os.path.join(cert_dir, 'key.pem'), 'wb') as f:
        f.write(key_pem)
    click.echo(f'Key written to {os.path.join(cert_dir, "key.pem")}')
    with open(os.path.join(cert_dir, 'csr.pem'), 'wb') as f:
        f.write(csr_pem)
    click.echo(f'CSR written to {os.path.join(cert_dir, "csr.pem")}')

    try:
        click.echo("Loading incluster configuration...")
        kubernetes.config.load_incluster_config()
    except Exception as e:
        click.echo("Exception loading incluster configuration: %s" % e)
        try:
            click.echo("Loading kubernetes configuration...")
            kubernetes.config.load_kube_config()
        except Exception as e:
            click.echo("Exception loading kubernetes configuration: %s" % e)
            raise click.Abort()

    configuration = kubernetes.client.Configuration()
    certificates_api = kubernetes.client.CertificatesV1beta1Api(kubernetes.client.ApiClient(configuration))

    certificate_signing_request_spec = kubernetes.client.models.V1beta1CertificateSigningRequestSpec(
        groups=["system:authenticated"],
        request=base64.b64encode(csr_pem).decode('utf-8').rstrip(),
        usages=[u"digital signature", u"key encipherment", u"server auth", u"client auth"],
    )

    metadata = kubernetes.client.models.V1ObjectMeta(
        name=csr_name,
    )

    certificate_signing_request = kubernetes.client.models.V1beta1CertificateSigningRequest(
        metadata=metadata,
        spec=certificate_signing_request_spec,
    )

    try:
        response = certificates_api.create_certificate_signing_request(certificate_signing_request)
    except ApiException as e:
        click.echo("Error from Kubernetes API: %s" % (e,))
        raise click.Abort()

    while True:
        click.echo("Checking for csr approval for %s" % (csr_name,))
        try:
            response = certificates_api.read_certificate_signing_request(csr_name, pretty=True)
        except ApiException as e:
            click.echo("Error from Kubernetes API: %s" % (e,))
        conditions = response.status.conditions or []
        if 'Approved' in [c.type for c in conditions]:
            click.echo('CSR Approved!')
            cert_pem = base64.b64decode(response.status.certificate)
            break
        click.echo("Waiting for csr approval for %s" % (csr_name,))
        time.sleep(5)

    with open(os.path.join(cert_dir, 'cert.pem'), 'wb') as f:
        f.write(cert_pem)
    click.echo(f'Certificate written to {os.path.join(cert_dir, "cert.pem")}')


if __name__ == '__main__':
    main()
