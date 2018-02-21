FROM alpine:3.7 as builder

ENV GOLDFISH_FORK=ewdurbin
ENV GOLDFISH_VERSION=v0.8.0post2
ENV GOLDFISH_SHASUM=74ce500b6f10168999bcdfb2cc2021d520762a30a0e1ec6a752aea89613e5bff

RUN apk add --update wget

RUN wget --quiet https://github.com/${GOLDFISH_FORK}/goldfish/releases/download/${GOLDFISH_VERSION}/goldfish-linux-amd64
RUN [ "$(sha256sum goldfish-linux-amd64)" == "$GOLDFISH_SHASUM  goldfish-linux-amd64" ]
RUN mv goldfish-linux-amd64 goldfish

RUN chmod +x goldfish

FROM scratch
COPY --from=builder /lib/libc.musl-x86_64.so.1 /lib64/ld-linux-x86-64.so.2
COPY --from=builder goldfish /bin/goldfish
