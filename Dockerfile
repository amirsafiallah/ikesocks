FROM alpine:3.19

LABEL org.opencontainers.image.title="ikesocks" \
      org.opencontainers.image.description="SOCKS5 proxy over IKEv2/IPsec" \
      org.opencontainers.image.source="https://github.com/amirsafiallah/ikesocks"

RUN apk add --no-cache \
        strongswan \
        dante-server \
        bash \
        iproute2 \
        iptables \
    && rm -rf /var/cache/apk/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE ${SOCKS_PORT:-1080}
STOPSIGNAL SIGTERM

ENTRYPOINT ["/entrypoint.sh"]
