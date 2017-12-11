import signal
import sys

import kubernetes
from kubernetes.client.rest import ApiException

import click


def signal_handler(signal, frame):
    click.echo('Exiting!')
    sys.exit(0)


signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)


@click.command()
@click.option('--api-group', default="certificates.k8s.io", help="apiGroup to check")
@click.option('--resource', default="certificatesigningrequests", help="Resource in apiGroup to check")
@click.option('--subresource', default="serverautoapprove", help="Subresource to check")
@click.option('--verb', default="create", help="Verb to check")
def main(api_group, resource, subresource, verb):
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
    authorization_api = kubernetes.client.AuthorizationV1Api(kubernetes.client.ApiClient(configuration))

    w = kubernetes.watch.Watch()
    latest_resource_version = 0

    while True:
        try:
            for event in w.stream(certificates_api.list_certificate_signing_request, resource_version=latest_resource_version, timeout_seconds=10):
                if event['type'] != "ADDED":
                    continue
                item = event['object']
                latest_resource_version = max(latest_resource_version, int(item.metadata.resource_version))

                try:
                    certificate = certificates_api.read_certificate_signing_request(item.metadata.name)
                except ApiException as e:
                    if e.status == 404:
                        continue
                    click.echo('Encournterd exception fetching CertificateSigningRequest %s: %s %s' % (item.metadata.name, e.status, e.reason))

                conditions = item.status.conditions or []
                if conditions:
                    click.echo(f'skipping {item.metadata.name} with status {",".join([c.type for c in item.status.conditions])}')
                    continue

                resource_attributes = kubernetes.client.V1ResourceAttributes(
                    group=api_group,
                    resource=resource,
                    subresource=subresource,
                    verb=verb,
                )
                subject_access_review_spec = kubernetes.client.V1SubjectAccessReviewSpec(
                    extra=item.spec.extra,
                    groups=item.spec.groups,
                    uid=item.spec.uid,
                    user=item.spec.username,
                    resource_attributes=resource_attributes,
                )
                subject_access_review = kubernetes.client.V1SubjectAccessReview(spec=subject_access_review_spec)

                try:
                    subject_access_review_response = authorization_api.create_subject_access_review(subject_access_review)
                except ApiException as e:
                    click.echo('Encountered exception creating SubjectAccessReview for %s: %s' % (item.spec.username, e))

                if not subject_access_review_response.status.allowed:
                    click.echo(f'skipping unauthorized {item.metadata.name}')
                    continue

                condition = kubernetes.client.models.V1beta1CertificateSigningRequestCondition(
                    type='Approved',
                    reason='Auto Approved',
                    message='Auto Approved by certificate-approver',
                )

                status = kubernetes.client.models.V1beta1CertificateSigningRequestStatus(
                    conditions=[condition],
                )

                item.status.conditions = [condition]
                click.echo(f'approving {item.metadata.name}')
                try:
                    certificates_api.replace_certificate_signing_request_approval(item.metadata.name, item)
                except ApiException as e:
                    click.echo('Encountered exception approving CertificateSigningRequest %s: %s %s' % (item.metadata.name, e.status, e.reason))

        except Exception as e:
            click.echo("Exception encountered: %s\n" % e)
            sys.exit(1)


if __name__ == '__main__':
    main()
