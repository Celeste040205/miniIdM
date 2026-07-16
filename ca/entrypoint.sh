#!/bin/sh
set -e

CA_DIR=/etc/fis-ca
CA_KEY="$CA_DIR/ca.key"
CA_CRT="$CA_DIR/ca.crt"
SERVER_FQDN="${SERVER_FQDN:-idm1.fis.epn.ec}"
SERVER_KEY="$CA_DIR/idm1.key"
SERVER_CSR="$CA_DIR/idm1.csr"
SERVER_CRT="$CA_DIR/idm1.crt"
SAN_CNF="$CA_DIR/san.cnf"

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

# 2. Certificado de servidor para idm1 (solo si no existe)
if [ ! -f "$SERVER_CRT" ]; then
    log "Generando certificado de servidor para ${SERVER_FQDN}..."

    cat > "$SAN_CNF" <<EOF
[req]
distinguished_name = dn
req_extensions = v3_req
prompt = no

[dn]
CN = ${SERVER_FQDN}

[v3_req]
subjectAltName = @alt_names
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = ${SERVER_FQDN}
DNS.2 = idm1
EOF

    openssl ecparam -name prime256v1 -genkey -noout -out "$SERVER_KEY"
    openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" -config "$SAN_CNF"
    openssl x509 -req -in "$SERVER_CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
        -out "$SERVER_CRT" -days 825 -extensions v3_req -extfile "$SAN_CNF"

    # Permisos abiertos porque el UID de openldap dentro de idm1 no coincide
    # con el UID que escribe estos archivos aqui en el contenedor de la CA
    # (son imagenes distintas). Para un lab esta bien; en produccion se
    # ajustaria con un UID compartido o un init-container que copie y aplique chown.
    chmod 644 "$CA_CRT" "$SERVER_CRT" "$SERVER_KEY"
else
    log "Certificado de servidor ya existe, no se regenera."
fi

log "Archivos en ${CA_DIR}:"
ls -la "$CA_DIR"

log "Manteniendo contenedor vivo..."
sleep infinity