FROM quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.11.0

COPY custom-entrypoint.sh /custom-entrypoint.sh
ENTRYPOINT ["/custom-entrypoint.sh"]

CMD ["/nginx-ingress-controller"]
