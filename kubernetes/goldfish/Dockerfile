FROM alpine:3.7 as builder

ENV VAULT_VERSION=0.9.0
ENV VAULT_SHASUM=801ce0ceaab4d2e59dbb35ea5191cfe8e6f36bb91500e86bec2d154172de59a4

ENV GOLDFISH_FORK=ewdurbin
ENV GOLDFISH_VERSION=v0.8.0post1
ENV GOLDFISH_SHASUM=dac4d1d7621e60dfd31a233443bd90d1e12288520bec23f270918e432e402b98

RUN apk add --update wget unzip

RUN wget --quiet https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip
RUN [ "$(sha256sum vault_${VAULT_VERSION}_linux_amd64.zip)" == "$VAULT_SHASUM  vault_${VAULT_VERSION}_linux_amd64.zip" ]
RUN unzip vault_${VAULT_VERSION}_linux_amd64.zip

RUN wget --quiet https://github.com/${GOLDFISH_FORK}/goldfish/releases/download/${GOLDFISH_VERSION}/goldfish-linux-amd64
RUN [ "$(sha256sum goldfish-linux-amd64)" == "$GOLDFISH_SHASUM  goldfish-linux-amd64" ]
RUN mv goldfish-linux-amd64 goldfish

RUN chmod +x goldfish vault

FROM scratch
COPY --from=builder /lib/libc.musl-x86_64.so.1 /lib64/ld-linux-x86-64.so.2
COPY --from=builder goldfish /bin/goldfish
COPY --from=builder vault /bin/vault
