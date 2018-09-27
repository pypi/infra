FROM registry:2.6.2

COPY custom-entrypoint.sh /custom-entrypoint.sh
ENTRYPOINT ["/custom-entrypoint.sh"]

CMD ["/etc/docker/registry/config.yml"]
