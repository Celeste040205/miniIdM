#!/bin/sh
set -e

CA_DIR=/etc/fis-ca
CA_KEY="$CA_DIR/ca.key"
CA_CRT="$CA_DIR/ca.crt"
log() { echo "[ca-entrypoint] $*"; }

mkdir -p "$CA_DIR"
cd "$CA_DIR"

# 1. CA raiz (solo si no existe)
if [ ! -f "$CA_KEY" ] || [ ! -f "$CA_CRT" ]; then
    log "Generando CA raiz (ECDSA prime256v1)..."
    openssl ecparam -name prime256v1 -genkey -noout -out "$CA_KEY"
    openssl req -new -x509 -key "$CA_KEY" -out "$CA_CRT" -days 3650 -subj "/CN=FIS-CA"
else
    log "CA raiz ya existe, no se regenera."
fi

# Funcion para generar certificados de servidor
generate_cert() {
    local FQDN="$1"
    local SHORT_NAME="${FQDN%%.*}"
    local KEY="$CA_DIR/${SHORT_NAME}.key"
    local CSR="$CA_DIR/${SHORT_NAME}.csr"
    local CRT="$CA_DIR/${SHORT_NAME}.crt"
    local CONF="$CA_DIR/${SHORT_NAME}_san.cnf"

    if [ ! -f "$CRT" ]; then
        log "Generando certificado de servidor para ${FQDN}..."

        cat > "$CONF" <<EOF
[req]
distinguished_name = dn
req_extensions = v3_req
prompt = no

[dn]
CN = ${FQDN}

[v3_req]
subjectAltName = @alt_names
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = ${FQDN}
DNS.2 = ${SHORT_NAME}
EOF

        openssl ecparam -name prime256v1 -genkey -noout -out "$KEY"
        openssl req -new -key "$KEY" -out "$CSR" -config "$CONF"
        openssl x509 -req -in "$CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
            -out "$CRT" -days 825 -extensions v3_req -extfile "$CONF"

        # Permisos abiertos para que coincida en contenedores distintos
        chmod 644 "$CRT" "$KEY"
        rm -f "$CSR" "$CONF"
        log "Certificado para ${FQDN} generado exitosamente."
    else
        log "Certificado para ${FQDN} ya existe, no se regenera."
    fi
}

# 2. Generar certificados para idm1 e idm2
generate_cert "${SERVER_FQDN:-idm1.fis.epn.ec}"
generate_cert "idm2.fis.epn.ec"

log "Archivos en ${CA_DIR}:"
ls -la "$CA_DIR"

log "Manteniendo contenedor vivo..."
sleep infinity