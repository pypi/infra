# PyPI Infrastructure

Primarily used for terraform configuration.

## Warehouse health checks

Fastly checks the two Warehouse processes separately:

* `Application` checks `/_health/web`, routed to `web`.
* `Application_API` checks `/_health/api`, routed to `web-api`.

Fastly sends `/simple…`, `/pypi/…/json…`, and `/_health/api` (with optional
`/…` suffixes) to the API backend. Matching ignores case, just like ingress.
Keep both sets of rules in sync. Uploads use a separate service and are unchanged.
