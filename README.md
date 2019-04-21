# PyPI Infrastructure

PyPI infrastructure is provisioned on AWS using Terraform and Kubernetes.


### k8s

This directory contains YAML manifests to provision a Third Party Resource to manage Let's Encrypt certificates.

### kubernetes

This directory contains Dockerfiles, YAML manifests, and helper scripts to setup [Cabotage](https://github.com/cabotage/cabotage-app) and associated services like Hashicorp Vault and Consul.

### lambda deployer

This directory contains the lambda-deployer binary to be deployed to AWS Lambda and bootstrap code written in Rust.

### terraform

This directory provisions the PyPI production infrastructure on AWS. In particular it provisions:

* DNS records using Route53
* Email with SES and Postmark
* PyPI filehosting using S3 and Fastly
* [PyPI](https://pypi.org/) using Fastly
* Documentation using Fastly
* Lambda functions for shipping Linehaul logs
