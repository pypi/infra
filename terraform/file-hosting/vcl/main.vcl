sub vcl_recv {
    declare local var.AWS-Access-Key-ID STRING;
    declare local var.AWS-Secret-Access-Key STRING;
    declare local var.S3-Bucket-Name STRING;

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
        error 803 "SSL is required";
    }

    # Requests that are for an *actual* file get disaptched to Amazon S3 instead of
    # to our typical backends. We need to setup the request to correctly access
    # S3 and to authorize ourselves to S3.
    if (req.backend == F_S3 && req.url ~ "^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/") {
        # Setup our environment to better match what S3 expects/needs
        set req.http.Host = var.S3-Bucket-Name ".s3.amazonaws.com";
        set req.http.Date = now;
        set req.url = regsuball(req.url, "\+", urlencode("+"));

        # Compute the Authorization header that S3 requires to be able to
        # access the files stored there.
        set req.http.Authorization = "AWS " var.AWS-Access-Key-ID ":" digest.hmac_sha1_base64(var.AWS-Secret-Access-Key, "GET" LF LF LF req.http.Date LF "/" var.S3-Bucket-Name req.url.path);
    }

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
    # header. We can't add these by default in S3, but we can add them here.
    if (beresp.status == 200 && req.url ~ "^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/") {
        set beresp.http.Cache-Control = "max-age=365000000, immutable, public";
        set beresp.ttl = 365000000s;
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
    set resp.http.Strict-Transport-Security = "max-age=31536000; includeSubDomains; preload";
    set resp.http.X-Frame-Options = "deny";
    set resp.http.X-XSS-Protection = "1; mode=block";
    set resp.http.X-Content-Type-Options = "nosniff";
    set resp.http.X-Permitted-Cross-Domain-Policies = "none";
    set resp.http.X-Robots-Header = "noindex";

    # If we're not executing a shielding request, and the URL is one of our file
    # URLs, and it's a GET request, and the response is either a 200 or a 304
    # then...
    if (!req.http.Fastly-FF
            && req.url.path ~ "^/packages/[a-f0-9]{2}/[a-f0-9]{2}/[a-f0-9]{60}/"
            && req.request == "GET"
            && http_status_matches(resp.status, "200")) {

        # We want to set CORS headers allowing files to be loaded cross-origin
        set resp.http.Access-Control-Allow-Methods = "GET";
        set resp.http.Access-Control-Allow-Origin = "*";

        # And we want to log an event stating that a download has taken place.
        log {"syslog "} req.service_id {" linehaul :: "} "2@" now "|" geoip.country_code "|" req.url.path "|" tls.client.protocol "|" tls.client.cipher "|" resp.http.x-amz-meta-project "|" resp.http.x-amz-meta-version "|" resp.http.x-amz-meta-package-type "|" req.http.user-agent;
    }

    # Unset a few headers set by Amazon that we don't really have a need/desire
    # to send to clients.
    if (!req.http.Fastly-FF) {
        unset resp.http.x-amz-replication-status;
        unset resp.http.x-amz-meta-python-version;
        unset resp.http.x-amz-meta-version;
        unset resp.http.x-amz-meta-package-type;
        unset resp.http.x-amz-meta-project;
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
    if (obj.status == 803) {
        set obj.status = 403;
        set obj.response = "SSL is required";
        set obj.http.Content-Type = "text/plain; charset=UTF-8";
        synthetic {"SSL is required."};
        return (deliver);
    }

}
