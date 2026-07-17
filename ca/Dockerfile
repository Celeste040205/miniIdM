FROM alpine:latest
RUN apk add --no-cache openssl dos2unix
WORKDIR /etc/fis-ca
COPY entrypoint.sh /entrypoint.sh
RUN dos2unix /entrypoint.sh && chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]