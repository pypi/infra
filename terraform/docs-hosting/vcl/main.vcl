sub vcl_recv {
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

#FASTLY recv

    # Ensure that all of our users are getting a HTTPS version of the page by
    # redirecting them if they are not using HTTPS.
    if (!req.http.Fastly-SSL) {
        error 801 "Force SSL";
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
    if (req.http.Fastly-SSL) {
        # This header is only meaningful over HTTPS
        set resp.http.Strict-Transport-Security = "max-age=31536000; includeSubDomains; preload";
    }
    set resp.http.X-Frame-Options = "deny";
    set resp.http.X-XSS-Protection = "1; mode=block";
    set resp.http.X-Content-Type-Options = "nosniff";
    set resp.http.X-Permitted-Cross-Domain-Policies = "none";

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
}
