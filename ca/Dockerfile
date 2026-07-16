FROM alpine:latest
RUN apk add --no-cache openssl
WORKDIR /etc/fis-ca
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]