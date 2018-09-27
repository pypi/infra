#!/bin/sh

set -e

cp /var/run/secrets/kubernetes.io/serviceaccount/ca.crt /usr/local/share/ca-certificates/
update-ca-certificates

exec /usr/bin/dumb-init "$@"
