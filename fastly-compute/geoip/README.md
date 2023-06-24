# geoip

Provides an authenticated service that serves Fastly geoip information for IP
addresses. This is useful for backfilling past events in services that have
transitioned to using geoip info and for retrieving geoip information when
requests do not transit the CDN layer.

## Local development

```shell
npm install
npx fastly compute serve --watch
```

This will start the service locally on port 7676 and reload on file changes.

In a separate terminal you can now test the service:

```shell
$ curl -s localhost:7676?ip=127.0.0.1 | jq '.'
{
  "Error": "Unauthorized"
}
$ curl -s -H "X-Secret: sup3rs3cr3t" localhost:7676?ip=127.0.0.1 | jq '.'
{
  "geo": {
    "city": "San Francisco",
    "continent": "NA",
    "country_code": "US",
    "country_code3": "USA",
    "country_name": "United States of America",
    "region": "CA"
  }
}
```
