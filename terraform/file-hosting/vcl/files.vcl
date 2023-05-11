sub vcl_recv {
    # Require authentication for curl -XPURGE requests, required for Segmented Caching
    set req.http.Fastly-Purge-Requires-Auth = "1";

    # Enable Segmented Caching for package URLS
    if (req.url ~ "^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/") {
        set req.enable_segmented_caching = true;
        if (req.url ~ "^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/(.*).metadata$") {
            # Don't enable segmented caching if we're serving a metadata file
            set req.enable_segmented_caching = false;
        }
    }

    # I'm not 100% sure on what this is exactly for, it was taken from the
    # Fastly documentation, however, what I *believe* it does is just ensure
    # that we don't serve a stale copy of the page from the shield node when
    # an edge node is requesting content.
    if (req.http.Fastly-FF) {
        set req.max_stale_while_revalidate = 0s;
    }

    # Some (Older) clients will send a hash fragment as part of the URL even
    # though that is a local only modification. This breaks this badly for the
    # files in S3, and in general it's just not needed.
    set req.url = regsub(req.url, "#.*$", "");

    # We do not support any kind of a query string for these files. Stripping them
    # out here will save on cache misses for when query strings get added by end
    # users for one reason or another.
    set req.url = req.url.path;

    # Currently Fastly does not provide a way to access response headers when
    # the response is a 304 response. This is because the RFC states that only
    # a limit set of headers should be sent with a 304 response, and the rest
    # are SHOULD NOT. Since this stripping happens *prior* to vcl_deliver being
    # ran, that breaks our ability to log on 304 responses. Ideally at some
    # point Fastly offers us a way to access the "real" response headers even
    # for a 304 response, but for now, we are going to remove the headers that
    # allow a conditional response to be made. If at some point Fastly does
    # allow this, then we can delete this code.
    if (!req.http.Fastly-FF
            && req.url.path ~ "^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/") {
        unset req.http.If-None-Match;
        unset req.http.If-Modified-Since;
    }

#FASTLY recv

    # We want to Force SSL for the WebUI by returning an error code directing people
    # to instead use HTTPS.
    if (!req.http.Fastly-SSL) {
        error 603 "SSL is required";
    }

    # Forbid clients without SNI support, except Fastly/cache-check (Note this is disabled at edge, but provide a fallback).
    if (!req.http.Fastly-FF && tls.client.servername == "" && req.http.User-Agent != "Fastly/cache-check") {
        error 604 "SNI is required";
    }

    # Check if our request was restarted for a package URL due to a 404,
    # Change our backend to S3 Archive to look for the file there, re-enable clustering and continue
    # https://www.slideshare.net/Fastly/advanced-vcl-how-to-use-restart
    if (req.restarts > 0 && req.url ~ "^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/") {
      set req.backend = F_S3_Archive;
      set req.http.Fastly-Force-Shield = "1";
      set req.http.Fallback-Backend = "1";
    }

    # Requests that are for an *actual* file get disaptched to object storage instead of
    # to our typical backends.

    # Do not bother to attempt to run the caching mechanisms for methods that
    # are not generally safe to cache.
    if (req.request != "HEAD" &&
        req.request != "GET" &&
        req.request != "FASTLYPURGE") {
      return(pass);
    }

    return(lookup);
}

sub vcl_fetch {
    # These are newer kinds of redirects which should be able to be cached by
    # default, even though Fastly doesn't currently have them in their default
    # list of cacheable status codes.
    if (http_status_matches(beresp.status, "303,307,308")) {
        set beresp.cacheable = true;
    }

    # If we successfully got a 404 response from B2 for a Package URL restart
    # to check S3 Archive for the file! (Note 403, which sucks but is apparently the
    # response you get for a non existent file from B2's S3 interop  when auth'd???
    if (
      req.restarts == 0 && req.backend == F_B2
      && req.url ~ "^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/"
      && (
        http_status_matches(beresp.status, "404")
        || http_status_matches(beresp.status, "403")
      )
    ) {
      restart;
    }

    # Handle 5XX (or any other unwanted status code)
    if (beresp.status >= 500 && beresp.status < 600) {
        # Deliver stale if the object is available
        if (stale.exists) {
            return(deliver_stale);
        }

        if (req.restarts < 1 && (req.request == "GET" || req.request == "HEAD")) {
            restart;
        }
    }


#FASTLY fetch

    # If we've gotten a 502 or a 503 from the backend, we'll go ahead and retry
    # the request.
    if ((beresp.status == 502 || beresp.status == 503) &&
            req.restarts < 1 &&
            (req.request == "GET" || req.request == "HEAD")) {
        restart;
    }

    # If we've restarted, then we'll record the number of restarts.
    if(req.restarts > 0 ) {
        set beresp.http.Fastly-Restarts = req.restarts;
    }

    # When we're fetching our files, we want to give them a super long Cache-Control
    # header. We can't add these by default in object storage, but we can add them here.
    if (http_status_matches(beresp.status, "200,206") && req.url ~ "^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/") {
        # Google sets an Expires header for private requests, we should drop this.
        unset beresp.http.expires;
        set beresp.http.Cache-Control = "max-age=365000000, immutable, public";
        set beresp.ttl = 365000000s;
        if (req.url == "/packages/aa/aa/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/aaaaaaaaa-0.0.0.tar.gz") {
            set beresp.http.Cache-Control = "max-age=0, immutable, public";
            set beresp.ttl = 0s;
        }
    }

    # Check if we are serving a .metadata file, which are stored uncompressed
    if (req.url ~ "^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/(.*).metadata$" ) {
        # Always set a Vary header, even if we don't end up compressing
        # the object, because the uncompressed version should only be
        # used when the request does NOT request the compressed one.
        if (!beresp.http.Vary ~ "Accept-Encoding") {
            if (beresp.http.Vary) {
                set beresp.http.Vary = beresp.http.Vary ", Accept-Encoding";
            } else {
                set beresp.http.Vary = "Accept-Encoding";
            }
        }

        # Perform compression if the client claims to understand it
        if (req.http.Accept-Encoding == "gzip") {
            set beresp.gzip = true;
        } else if (req.http.Accept-Encoding == "br") {
            set beresp.brotli = true;
        } else {
            set beresp.gzip = false;
            set beresp.brotli = false;
        }
    }

    # If there is a Set-Cookie header, we'll ensure that we do not cache the
    # response.
    if (beresp.http.Set-Cookie) {
        set req.http.Fastly-Cachetype = "SETCOOKIE";
        return (pass);
    }

    # If we've gotten an error after the restarts we'll deliver the response
    # with a very short cache time.
    if (http_status_matches(beresp.status, "500,502,503")) {
        set req.http.Fastly-Cachetype = "ERROR";
        set beresp.ttl = 1s;
        set beresp.grace = 5s;
        return (deliver);
    }

    return(deliver);
}



sub vcl_hit {
#FASTLY hit

    # If the object we have isn't cacheable, then just serve it directly
    # without going through any of the caching mechanisms.
    if (!obj.cacheable) {
        return(pass);
    }

    return(deliver);
}

sub vcl_miss {
  declare local var.B2AccessKey STRING;
  declare local var.B2SecretKey STRING;
  declare local var.B2Bucket STRING;
  declare local var.B2Region STRING;

  declare local var.AWSArchiveAccessKeyID STRING;
  declare local var.AWSArchiveSecretAccessKey STRING;
  declare local var.AWSArchiveBucket STRING;
  declare local var.AWSArchiveRegion STRING;

  declare local var.canonicalHeaders STRING;
  declare local var.signedHeaders STRING;
  declare local var.canonicalRequest STRING;
  declare local var.canonicalQuery STRING;
  declare local var.stringToSign STRING;
  declare local var.dateStamp STRING;
  declare local var.signature STRING;
  declare local var.scope STRING;

#FASTLY miss

  if (req.backend == F_S3_Archive) {
      set bereq.http.x-amz-content-sha256 = digest.hash_sha256("");
      set bereq.http.x-amz-date = strftime({"%Y%m%dT%H%M%SZ"}, now);
      set bereq.http.host = var.AWSArchiveBucket ".s3." var.AWSArchiveRegion ".amazonaws.com";
      set bereq.url = querystring.remove(bereq.url);
      set bereq.url = regsuball(bereq.url, "\+", urlencode("+"));
      set bereq.url = regsuball(urlencode(urldecode(bereq.url.path)), {"%2F"}, "/");
      set var.dateStamp = strftime({"%Y%m%d"}, now);
      set var.canonicalHeaders = ""
        "host:" bereq.http.host LF
        "x-amz-content-sha256:" bereq.http.x-amz-content-sha256 LF
        "x-amz-date:" bereq.http.x-amz-date LF
      ;
      set var.canonicalQuery = "";
      set var.signedHeaders = "host;x-amz-content-sha256;x-amz-date";
      set var.canonicalRequest = ""
        "GET" LF
        bereq.url.path LF
        var.canonicalQuery LF
        var.canonicalHeaders LF
        var.signedHeaders LF
        digest.hash_sha256("")
      ;

      set var.scope = var.dateStamp "/" var.AWSArchiveRegion "/s3/aws4_request";

      set var.stringToSign = ""
        "AWS4-HMAC-SHA256" LF
        bereq.http.x-amz-date LF
        var.scope LF
        regsub(digest.hash_sha256(var.canonicalRequest),"^0x", "")
      ;

      set var.signature = digest.awsv4_hmac(
        var.AWSArchiveSecretAccessKey,
        var.dateStamp,
        var.AWSArchiveRegion,
        "s3",
        var.stringToSign
      );

      set bereq.http.Authorization = "AWS4-HMAC-SHA256 "
        "Credential=" var.AWSArchiveAccessKeyID "/" var.scope ", "
        "SignedHeaders=" var.signedHeaders ", "
        "Signature=" + regsub(var.signature,"^0x", "")
      ;
      unset bereq.http.Accept;
      unset bereq.http.Accept-Language;
      unset bereq.http.User-Agent;
      unset bereq.http.Fastly-Client-IP;
  }

  if (req.backend == F_B2) {
      set bereq.http.x-amz-content-sha256 = digest.hash_sha256("");
      set bereq.http.x-amz-date = strftime({"%Y%m%dT%H%M%SZ"}, now);
      set bereq.http.host = var.B2Bucket ".s3." var.B2Region ".backblazeb2.com";
      set bereq.url = querystring.remove(bereq.url);
      set bereq.url = regsuball(bereq.url, "\+", urlencode("+"));
      set bereq.url = regsuball(urlencode(urldecode(bereq.url.path)), {"%2F"}, "/");
      set var.dateStamp = strftime({"%Y%m%d"}, now);
      set var.canonicalHeaders = ""
        "host:" bereq.http.host LF
        "x-amz-content-sha256:" bereq.http.x-amz-content-sha256 LF
        "x-amz-date:" bereq.http.x-amz-date LF
      ;
      set var.canonicalQuery = "";
      set var.signedHeaders = "host;x-amz-content-sha256;x-amz-date";
      set var.canonicalRequest = ""
        "GET" LF
        bereq.url.path LF
        var.canonicalQuery LF
        var.canonicalHeaders LF
        var.signedHeaders LF
        digest.hash_sha256("")
      ;

      set var.scope = var.dateStamp "/" var.B2Region "/s3/aws4_request";

      set var.stringToSign = ""
        "AWS4-HMAC-SHA256" LF
        bereq.http.x-amz-date LF
        var.scope LF
        regsub(digest.hash_sha256(var.canonicalRequest),"^0x", "")
      ;

      set var.signature = digest.awsv4_hmac(
        var.B2SecretKey,
        var.dateStamp,
        var.B2Region,
        "s3",
        var.stringToSign
      );

      set bereq.http.Authorization = "AWS4-HMAC-SHA256 "
        "Credential=" var.B2AccessKey "/" var.scope ", "
        "SignedHeaders=" var.signedHeaders ", "
        "Signature=" + regsub(var.signature,"^0x", "")
      ;
      unset bereq.http.Accept;
      unset bereq.http.Accept-Language;
      unset bereq.http.User-Agent;
      unset bereq.http.Fastly-Client-IP;
  }

}

sub vcl_deliver {
    # If this is an error and we have a stale response available, restart so
    # that we can pick it up and serve it.
    if (resp.status >= 500 && resp.status < 600) {
        if (stale.exists) {
            restart;
        }
    }

#FASTLY deliver

    # Unset headers that we don't need/want to send on to the client because
    # they are not generally useful.
    unset resp.http.Via;

    # Set our standard security headers, we do this in VCL rather than in
    # the backend itself so that we always get these headers, regardless of the
    # origin server being used.
    if (req.http.Fastly-SSL) {
        # This header is only meaningful over HTTPS
        set resp.http.Strict-Transport-Security = "max-age=31536000; includeSubDomains; preload";
    }
    set resp.http.X-Frame-Options = "deny";
    set resp.http.X-XSS-Protection = "1; mode=block";
    set resp.http.X-Content-Type-Options = "nosniff";
    set resp.http.X-Permitted-Cross-Domain-Policies = "none";
    set resp.http.X-Robots-Header = "noindex";

    # If we're not executing a shielding request, and the URL is one of our file
    # URLs, and it's a GET request, and the response is either a 200 or a 206
    # then...
    if (!req.http.Fastly-FF
            && req.url.path ~ "^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/"
            && (req.request == "GET" || req.request == "OPTIONS")
            && http_status_matches(resp.status, "200,206")) {

        # We want to set CORS headers allowing files to be loaded cross-origin
        unset resp.http.X-Permitted-Cross-Domain-Policies;
        set resp.http.Access-Control-Allow-Methods = "GET, OPTIONS";
        set resp.http.Access-Control-Allow-Headers= "Range";
        set resp.http.Access-Control-Allow-Origin = "*";
    }

    # Rename or unset a few headers to send to clients.
    if (!req.http.Fastly-FF) {
        # Rename PyPI specific headers for file metadata, used by linehaul
        set resp.http.x-pypi-file-python-version = resp.http.x-amz-meta-python-version;
        set resp.http.x-pypi-file-version = resp.http.x-amz-meta-version;
        set resp.http.x-pypi-file-package-type = resp.http.x-amz-meta-package-type;
        set resp.http.x-pypi-file-project = resp.http.x-amz-meta-project;

        # Unset Amazon/Google headers that shouldn't be exposed to clients
        unset resp.http.x-amz-replication-status;
        unset resp.http.x-amz-meta-python-version;
        unset resp.http.x-amz-meta-version;
        unset resp.http.x-amz-meta-package-type;
        unset resp.http.x-amz-meta-project;
        unset resp.http.x-guploader-uploadid;
        unset resp.http.x-goog-storage-class;
    }

    return(deliver);
}



sub vcl_error {
#FASTLY error

    # If we have a 5xx error and there is a stale object available, then we
    # will deliver that stale object.
    if (obj.status >= 500 && obj.status < 600) {
        if (stale.exists) {
            return(deliver_stale);
        }
    }

    # Handle our "error" conditions which are really just ways to set synthetic
    # responses.
    if (obj.status == 603) {
        set obj.status = 403;
        set obj.response = "SSL is required";
        set obj.http.Content-Type = "text/plain; charset=UTF-8";
        synthetic {"SSL is required."};
        return (deliver);
    }

    if (obj.status == 604 ) {
        set obj.status = 403;
        set obj.response = "SNI is required";
        set obj.http.Content-Type = "text/plain; charset=UTF-8";
        synthetic {"SNI is required."};
        return (deliver);
    }

}


sub vcl_log {
    declare local var.Ship-Logs-To-Line-Haul BOOL;

#FASTLY log

    # If we're not executing a shielding request, and the URL is one of our file
    # URLs, and it's a GET request, and the response is either a 200 or a 206
    # then...
    if (!req.http.Fastly-FF
            && req.url.path ~ "^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/"
            && (req.request == "GET" || req.request == "OPTIONS")
            && http_status_matches(resp.status, "200,206")) {

        # We want to log an event stating that a download has taken place.
        if (var.Ship-Logs-To-Line-Haul) {  # Only log for linehaul if enabled
            if (!segmented_caching.is_inner_req) {  # Skip logging if it is an "inner_req" fetching just a segment of the file
                log {"syslog "} req.service_id {" Linehaul GCS :: "} "download|" now "|" client.geo.country_code "|" req.url.path "|" tls.client.protocol "|" tls.client.cipher "|" resp.http.x-pypi-file-project "|" resp.http.x-pypi-file-version "|" resp.http.x-pypi-file-package-type "|" req.http.user-agent;
            }
        }

    }
}
