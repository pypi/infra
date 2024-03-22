# This snippet helps Fastly run the game at https://toppops.fastlylabs.com/, which we
# use as part of events and meetups to help people understand edge networks.
#
# If this code is suspected of causing problems, it can safely be removed, but please
# let us know (fast-forward@fastly.com)

table toppops_config {
  "datacenters": "ACC, AKL, BOG, CHI, EXE, FJR, HEL, JNB, LGB, MAD, PER, QPG, TYO",
  "sample_percent": "3"
}

# This is likely a second declaration of vcl_log which is fine,
# Fastly will execute them in turn as if they are one subroutine.
sub vcl_log {
  if (${fastly_toppops_enabled} && fastly.ff.visits_this_service == 0) {
    declare local var.dcpattern STRING;
    declare local var.thisdc STRING;
    set var.dcpattern = "," regsuball(table.lookup(toppops_config, "datacenters"), "\s", "") ",";
    set var.thisdc = "," server.datacenter ",";
    if (
      std.strstr(var.dcpattern, var.thisdc) &&
      randombool(std.atoi(table.lookup(toppops_config, "sample_percent", "0")), 100)
    ) {
      log "syslog " req.service_id " toppops-collector :: "
        server.datacenter " "
        time.start.usec " "
        time.elapsed.usec " "
        if (fastly_info.is_h2, "1", "0")
        if (req.is_ipv6, "1", "0")
        if (req.is_ssl, "1", "0")
        if (fastly_info.state ~ "^HIT", "1", "0") " "
        accept.language_lookup("aa:ab:ae:af:ak:am:an:ar:as:av:ay:az:ba:be:bg:bh:bi:bm:bn:bo:br:ca:ce:ch:co:cr:cs:cu:cv:cy:da:de:dv:dz:ee:el:en:eo:es:et:eu:fa:ff:fi:fj:fo:fr:fy:ga:gd:gl:gn:gu:gv:ha:he:hi:ho:ht:hu:hy:hz:ia:ie:ig:ii:ik:io:is:it:iu:iw:ja:ji:jv:jw:ka:kg:ki:kj:kk:kl:km:kn:ko:kr:ks:ku:kv:kw:ky:la:lb:lg:li:ln:lo:lt:lu:lv:mg:mh:mi:mk:ml:mn:mo:mr:ms:mt:my:na:nd:ne:ng:nl:no:nr:nv:ny:oc:oj:om:or:os:pa:pi:pl:ps:pt:qu:rm:rn:ro:ru:rw:sa:sc:sd:se:sg:sh:si:sk:sl:sm:sn:so:sq:ss:st:su:sv:sw:ta:te:tg:th:ti:tk:tl:tn:to:tr:ts:tt:ty:ug:uk:ur:uz:ve:vi:vo:wa:wo:xh:yi:yo:za:zh:zu", "en", req.http.Accept-Language) " "
        client.socket.cwnd " "
        client.socket.tcpi_pacing_rate " "
        client.socket.tcpi_min_rtt
      ;
    }
  }
}
