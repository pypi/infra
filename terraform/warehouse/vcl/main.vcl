sub vcl_recv {
    # Require authentication for curl -XPURGE requests.
    set req.http.Fastly-Purge-Requires-Auth = "1";

    declare local var.Warehouse-Ip-Salt STRING;

    # Prevent edge from caching stale content served from shield
    # https://developer.fastly.com/learning/concepts/stale/#shielding-considerations
    if (fastly.ff.visits_this_service > 0) {
        set req.max_stale_while_revalidate = 0s;
    }

    # Some (Older) clients will send a hash fragment as part of the URL even
    # though that is a local only modification. This breaks this badly for the
    # files in S3, and in general it's just not needed.
    set req.url = regsub(req.url, "#.*$", "");

    # Fastly does some normalization of the Accept-Encoding header so that it
    # reduces the number of cached copies (when served with the common,
    # Vary: Accept-Encoding) that are cached for any one URL. This makes a lot
    # of sense, except for the fact that we want to enable brotli compression
    # for our static files. Thus we need to work around the normalized encoding
    # in a way that still minimizes cached copies, but which will allow our
    # static files to be served using brotli.
    if (req.url ~ "^/static/" && req.http.Fastly-Orig-Accept-Encoding) {
        if (req.http.User-Agent ~ "MSIE 6") {
            # For that 0.3% of stubborn users out there
            unset req.http.Accept-Encoding;
        } elsif (req.http.Fastly-Orig-Accept-Encoding ~ "br") {
            set req.http.Accept-Encoding = "br";
        } elsif (req.http.Fastly-Orig-Accept-Encoding ~ "gzip") {
            set req.http.Accept-Encoding = "gzip";
        } else {
            unset req.http.Accept-Encoding;
        }
    }

    # We want to normalize our Accept header for our /simple/ index pages to
    # support the content negotiation feature added in PEP 691.
    if (req.url ~ "^/simple/" && fastly.ff.visits_this_service == 0) {
        declare local var.query_format STRING;

        set var.query_format = querystring.get(req.url, "format");
        if (var.query_format == "text/html" ||
                var.query_format == "application/vnd.pypi.simple.v1+html" ||
                var.query_format == "application/vnd.pypi.simple.v1+json" ||
                var.query_format == "application/vnd.pypi.simple.latest+html" ||
                var.query_format == "application/vnd.pypi.simple.latest+json") {
            set req.http.Accept = var.query_format;
        } else {
            # This is a little weird here, but Fastly's accept.media_lookup function
            # has a few properties that make this odd:
            #
            # - Content types may only be mentioned once in the first 3 parameters.
            # - If you have a foo/whatever type, then a default for foo/* must be
            #   included.
            # - You must have a fallback defined.
            #
            # These combined makes things awkward, because we only have a single text/*
            # type that we support, text/html, AND we want that same type to be our
            # ultimate fallback.
            #
            # It's also slightly weird to have a default for application/*, but not the
            # end of the world.
            #
            # The big thing we do here is fallback to text/invalid, then later we check
            # for that, and if iti is that, then we switch it back to text/html.
            set req.http.Accept = accept.media_lookup(
                "application/vnd.pypi.simple.v1+json:application/vnd.pypi.simple.latest+html:application/vnd.pypi.simple.latest+json",
                "text/invalid",
                "application/vnd.pypi.simple.v1+html:text/html",
                req.http.Accept
            );

            if (req.http.Accept == "text/invalid") {
                set req.http.Accept = "text/html";
            }
        }

        # The "latest" versions are aliases, but they're aliases that don't get reflected in
        # the returned Content-Type, so we do this before stashing our real Content-Type.
        if (req.http.Accept == "application/vnd.pypi.simple.latest+html") {
            set req.http.Accept = "application/vnd.pypi.simple.v1+html";
        } elsif (req.http.Accept == "application/vnd.pypi.simple.latest+json") {
            set req.http.Accept = "application/vnd.pypi.simple.v1+json";
        }

        # We want to stash what our "real" content type is, prior to doing any sort of aliasing
        # for cache efficiency, so that we can serve it correctly.
        set req.http.Warehouse-Real-Content-Type = req.http.Accept;

        # text/html is really just application/vnd.pypi.simple.v1+html, so we'll turn it into that
        if (req.http.Accept == "text/html") {
            set req.http.Accept = "application/vnd.pypi.simple.v1+html";
        }
    }

    # Most of the URLs in Warehouse do not support or require any sort of query
    # parameter. If we strip these at the edge then we'll increase our cache
    # efficiency when they won't otherwise change the output of the pages.
    #
    # This will match any URL except those that start with:
    #
    #   * /admin/
    #   * /locale/
    #   * /manage/
    #   * /search/
    #   * /account/login/
    #   * /account/logout/
    #   * /account/register/
    #   * /account/reset-password/
    #   * /account/verify-email/
    #   * /account/verify-organization-role/
    #   * /account/two-factor/
    #   * /account/webauthn-authenticate/
    #   * /pypi
    if (req.url.path !~ "^/(admin/|locale/|manage/|search(/|$)|account/(login|logout|register|reset-password|verify-email|verify-organization-role|two-factor|webauthn-authenticate|recovery-code)/|pypi)") {
        set req.url = req.url.path;
    }

    # Normalize project name in JSON API and collapse requests, redirect if
    # trailing slash present.
    if (req.url.path ~ "^/pypi/([^/]+)(/?[^/]+)?/json/?$") {
        declare local var.json_url STRING;
        if (re.group.2) {
            set var.json_url = "/pypi/" + std.tolower(regsuball(re.group.1, "(\.|_|-)+", "-")) + re.group.2 + "/json";
        } else {
            set var.json_url = "/pypi/" + std.tolower(regsuball(re.group.1, "(\.|_|-)+", "-")) + "/json";
        }
        if (req.url.path ~ "/$") {
            set req.http.Location = var.json_url;
            error 650 "Redirect";
        }
        set req.url = var.json_url;
    }

    # Sort all of our query parameters, this will ensure that the same query
    # parameters in a different order will end up being represented as the same
    # thing, reducing cache misses due to ordering differences.
    set req.url = boltsort.sort(req.url);

    # Synthesize a custom header for the locale if set, so we can vary on this
    # instead of the entire cookie, only do this on the edge. Shields should
    # ignore cookies.
    if (!req.http.Fastly-FF) {
        if (req.http.Cookie:_LOCALE_ && req.http.Cookie:_LOCALE_ != "") {
            # If set, language from cookie always wins
            set req.http.PyPI-Locale = req.http.Cookie:_LOCALE_;
        } else {
            # Lookup in Accept-Language header, fallback to "en" if no match found in supported languages
            # This list should mirror the KNOWN_LOCALES identifier list in https://github.com/pypi/warehouse/blob/main/warehouse/i18n/__init__.py
            # Note that the format for tags may be different than those in KNOWN_LOCALES
            # reference https://www.iana.org/assignments/language-subtag-registry/language-subtag-registry for correct values.
            set req.http.Accept-Language = accept.language_lookup("en:es:fr:ja:pt-BR:uk:el:de:zh-Hans:zh-Hant:ru:he:eo", "en", req.http.Accept-Language);
            set req.http.PyPI-Locale = req.http.Accept-Language;

            if (!req.http.PyPI-Locale) {
                # Safety-check: If PyPI-Locale is empty, default to "en"
                set req.http.PyPI-Locale = "en";
            }
        }
    }

    # Pass the client IP address back to the backend.
    if (req.http.Fastly-Client-IP) {
        set req.http.Warehouse-IP = req.http.Fastly-Client-IP;

        # Salt & hash the Client IP address
        declare local var.client_ip STRING;
        declare local var.hashed_ip STRING;

        # Concatenate the client IP address and the salt
        set var.client_ip = req.http.Fastly-Client-IP + var.Warehouse-Ip-Salt;

        # Hash the concatenated string
        set var.hashed_ip = digest.hash_sha256(var.client_ip);

        # TODO: After backend is updated, replace or remove `req.http.Warehouse-IP` above
        set req.http.Warehouse-Hashed-IP = var.hashed_ip;

        # Geolocate the client IP address.
        # Set distinct headers for country, region, and city.
        # See https://developer.fastly.com/reference/vcl/variables/geolocation/
        # Any placeholder values for reserved blocks are sent through
        # and left to pypi/warehouse on how to process
        set req.http.Warehouse-Continent-Code = client.geo.continent_code;
        set req.http.Warehouse-Country-Code = client.geo.country_code;
        set req.http.Warehouse-Country-Code3 = client.geo.country_code3;
        set req.http.Warehouse-Country-Name = client.geo.country_name;
        set req.http.Warehouse-Region = client.geo.region;
        set req.http.Warehouse-City = client.geo.city;
    }

#FASTLY recv


    # We want to Force SSL for the WebUI by redirecting to the HTTPS version of
    # the page, however for API calls we want to return an error code directing
    # people to instead use HTTPS.
    if (!req.http.Fastly-SSL) {

        # The /simple/ and /packages/ API.
        if (req.url ~ "^/(simple|packages)") {
            error 603 "SSL is required";
        }

        # The Legacy JSON API.
        if (req.url ~ "^/pypi/.+/json$") {
            error 603 "SSL is required";
        }

        # The Legacy ?:action= API.
        if (req.url ~ "^/pypi.*(\?|&)=:action") {
            error 603 "SSL is required";
        }

        # If we're on the /pypi page and we've received something other than a
        # GET or HEAD request, then we have no way to determine if a particular
        # request is an API call or not because it'll be in the request body
        # and that isn't available to us here. So in those cases, we won't
        # do a redirect.
        if (req.url ~ "^/pypi") {
            if (req.request == "GET" || req.request == "HEAD") {
                error 801 "Force SSL";
            }
        }
        else {
            # This isn't a /pypi URL so we'll just unconditionally redirect to
            # HTTPS.
            error 801 "Force SSL";
        }
    }

    # Forbid clients without SNI support, except Fastly/cache-check (Note this is disabled at edge, but provide a fallback).
    if (!req.http.Fastly-FF && tls.client.servername == "" && req.http.User-Agent != "Fastly/cache-check") {
        error 604 "SNI is required";
    }

    # Disable XMLRPC Search
    if ((req.url.path ~ "^/pypi$" || req.url.path ~ "^/pypi/$") &&
        req.http.Content-Type ~ "text/xml" &&
        req.body ~ "<methodName>search</methodName>") {
            error 667 "Disable XMLRPC Search";
    }

    # We need to redirect all of the existing domain names to the new domain name,
    # this includes the temporary domain names that Warehouse had, as well as the
    # existing legacy domain name. This is purposely being done *after* the HTTPS
    # checks so that we can force clients to utilize HTTPS.
    if (std.tolower(req.http.host) ~ "^(${join("|", extra_domains)})$") {
        # For HTTP GET/HEAD requests, we'll simply issue a 301 redirect, because that
        # has the widest support and is a permanent redirect. However, it has the
        # disadvantage of changing a POST to a GET, so for POST, etc we will attempt
        # to use a 308 redirect, which will keep the method. The 308 redirect is newer
        # and older may tools may not support them, so we may need to revist this.
        if (req.request == "GET" || req.request == "HEAD") {
            # Handle our GET/HEAD requests with a 301 redirect.
            set req.http.Location = "https://${domain}" req.url;
            error 650 "Redirect to Primary Domain";
        } else if (req.request == "POST" &&
                   std.tolower(req.http.host) == "${extra_domains[0]}" &&
                   (req.url.path ~ "^/pypi$" || req.url.path ~ "^/pypi/$") &&
                   req.http.Content-Type ~ "text/xml") {
            # The one exception to this, is XML-RPC requests to pypi.python.org, which
            # we want to silently rewrite to continue to function as if it was hitting
            # the new Warehouse endpoints. All we really need to do here is to fix
            # the Host header, and everything else will just continue to work.
            set req.http.Host = "${domain}";
        } else {
            # Finally, handle our other methods with a 308 redirect.
            set req.http.Location = "https://${domain}" req.url;
            error 651 "Redirect to Primary Domain";
        }
    }

    # There is some goofy tool that is slamming us with requests from go-http-client User-Agents
    # that causes redirect storms when it runs.
    if (req.http.User-Agent ~ "^[gG]o-http-client" && req.url ~ "^/simple" && req.url !~ "/$") {
      error 666 "go-http-client redirect";
    }
    if (req.http.User-Agent == "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.111 Safari/537.36" && req.url ~ "^/simple" && req.url !~ "/$") {
      error 668 "mock-webkit-client redirect";
    }

    # We have a number of items that we'll pass back to the origin.
    # Set a header to tell the backend if we're using https or http.
    if (req.http.Fastly-SSL) {
        set req.http.Warehouse-Proto = "https";
    } else {
        set req.http.Warehouse-Proto = "http";
    }

    # Pass the real host value back to the backend.
    if (req.http.Host) {
        set req.http.Warehouse-Host = req.http.host;
    }

    # On a POST, we want to skip the shielding and hit backends directly.
    if (req.request == "POST") {
        set req.backend = F_Application;
    }

    # Do not bother to attempt to run the caching mechanisms for methods that
    # are not generally safe to cache.
    if (req.request != "HEAD" &&
        req.request != "GET" &&
        req.request != "FASTLYPURGE") {
      return(pass);
    }

    # We don't ever want to cache our health URL. Outside systems should be
    # able to use it to reach past Fastly and get an end to end health check.
    if (req.url == "/_health/") {
        return(pass);
    }

    # We never want to cache our admin URLs, while this should be "safe" due to
    # the architecure of Warehouse, it'll just be easier to debug issues if
    # these always are uncached.
    if (req.url ~ "^/admin/") {
        return(pass);
    }

    # Finally, return the default lookup action.
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

        # Else go to vcl_error to deliver a synthetic
        error 503;
    }


#FASTLY fetch


    # Trigger a "SSL is required" error if the backend has indicated to do so.
    if (beresp.http.X-Fastly-Error == "603") {
        error 603 "SSL is required";
    }

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

    # If the response has the private Cache-Control directive then we won't
    # cache it.
    if (beresp.http.Cache-Control ~ "private") {
        set req.http.Fastly-Cachetype = "PRIVATE";
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

    # Apply a default TTL if there isn't a max-age or s-maxage.
    if (beresp.http.Expires ||
            beresp.http.Surrogate-Control ~ "max-age" ||
            beresp.http.Cache-Control ~"(s-maxage|max-age)") {
        # Keep the ttl here
    }
    else {
        # Apply the default ttl
        set beresp.ttl = 60s;
    }

    # Actually deliver the fetched response.
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

    # Serve the correct Content Type, but only if our returned content type matches our
    # accept content type.
    if (fastly.ff.visits_this_service == 0) {
        if (req.http.Warehouse-Real-Content-Type && resp.http.Content-Type == req.http.Accept) {
            set resp.http.Content-Type = req.http.Warehouse-Real-Content-Type;
        }
    }

    # Hide the existence of PyPI-Locale header from downstream
    if (resp.http.Vary && !req.http.Fastly-FF) {
        set resp.http.Vary = regsub(resp.http.Vary, "PyPI-Locale", "Cookie");
    }

    # Unset headers that we don't need/want to send on to the client because
    # they are not generally useful.
    unset resp.http.Via;

    # The Age header will reflect how long an item has been in the Varnish cache.
    # If present, clients will calculate `cache duration = max-age - Age` to see
    # how long they should cache for. We drop the header so clients will use max-age.
    # See http://book.varnish-software.com/4.0/chapters/HTTP.html#age and
    # https://tools.ietf.org/html/rfc7234#section-4.2.3
    unset resp.http.Age;

    # Set our standard security headers, we do this in VCL rather than in
    # Warehouse itself so that we always get these headers, regardless of the
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

        set obj.http.Content-Type = "text/html; charset=utf-8";
        synthetic {"${pretty_503}"};
        return(deliver);
    }

    if (obj.status == 603) {
        set obj.status = 403;
        set obj.response = "SSL is required";
        set obj.http.Content-Type = "text/plain; charset=UTF-8";
        synthetic {"SSL is required."};
        return (deliver);
    } else if (obj.status == 604 ) {
        set obj.status = 403;
        set obj.response = "SNI is required";
        set obj.http.Content-Type = "text/plain; charset=UTF-8";
        synthetic {"SNI is required."};
        return (deliver);
    } else if (obj.status == 650) {
        set obj.status = 301;
        set obj.http.Location = req.http.Location;
        set obj.http.Content-Type = "text/html; charset=UTF-8";
        synthetic {"<html><head><title>301 Moved Permanently</title></head><body><center><h1>301 Moved Permanently</h1></center></body></html>"};
        return(deliver);
    } else if (obj.status == 651) {
        set obj.status = 308;
        set obj.http.Location = req.http.Location;
        set obj.http.Content-Type = "text/html; charset=UTF-8";
        synthetic {"<html><head><title>308 Permanent Redirect</title></head><body><center><h1>308 Permanent Redirect</h1></center></body></html>"};
        return(deliver);
    } else if (obj.status == 666) {
        set obj.status = 406;
        set obj.http.Content-Type = "text/plain; charset=UTF-8";
        synthetic {"Go-http-client User-Agents are currently blocked from accessing /simple resources without a trailing slash. This causes a redirect to the canonicalized URL with the trailing slash. PyPI maintainers have been struggling to handle a piece of software with this User-Agent overloading our backends with requests resulting in redirects. Please contact admin@pypi.org if you have information regarding what this software may be."};
        return (deliver);
    } else if (obj.status == 667) {
        set obj.status = 200;
        set obj.http.Content-Type = "text/xml; charset=UTF-8";
        synthetic "<?xml version='1.0'?><methodResponse><fault><value><struct><member><name>faultCode</name><value><int>-32500</int></value></member><member><name>faultString</name><value><string>RuntimeError: PyPI no longer supports 'pip search' (or XML-RPC search). Please use https://${domain}/search (via a browser) instead. See https://warehouse.pypa.io/api-reference/xml-rpc.html#deprecated-methods for more information.</string></value></member></struct></value></fault></methodResponse>";
        return (deliver);
    } else if (obj.status == 668) {
        set obj.status = 406;
        set obj.http.Content-Type = "text/plain; charset=UTF-8";
        synthetic {"Mock WebKit User-Agents are currently blocked from accessing /simple resources without a trailing slash. This causes a redirect to the canonicalized URL with the trailing slash. PyPI maintainers have been struggling to handle a piece of software with this User-Agent overloading our backends with requests resulting in redirects. Please contact admin@pypi.org if you have information regarding what this software may be."};
        return (deliver);
    }

}
