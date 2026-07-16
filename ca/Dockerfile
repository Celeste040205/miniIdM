FROM alpine:latest
RUN apk add --no-cache openssl
WORKDIR /etc/fis-ca
# Comando para generar los certificados dentro del contenedor al construir
CMD ["sh", "-c", "openssl ecparam -name prime256v1 -genkey -noout -out ca.key && \
     openssl req -new -x509 -key ca.key -out ca.crt -subj '/CN=FIS-CA' && \
     sleep infinity"]