#!/bin/bash
set -euo pipefail

REALM="${REALM:-FIS.EPN.EC}"
FQDN="${FQDN:-webserver.fis.epn.ec}"
SHARED_DIR="/etc/krb5kdc/shared"

log() { echo "[web-entrypoint] $*"; }

cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = ${REALM}
    dns_lookup_realm = false
    dns_lookup_kdc = false
    rdns = false

[realms]
    ${REALM} = {
        kdc = idm1.fis.epn.ec
        kdc = idm2.fis.epn.ec
        admin_server = idm1.fis.epn.ec
    }

[domain_realm]
    .fis.epn.ec = ${REALM}
    fis.epn.ec = ${REALM}
EOF

log "Esperando keytab HTTP/webserver generado por idm1..."
while [ ! -f "${SHARED_DIR}/webserver.keytab" ]; do
    sleep 2
done
cp "${SHARED_DIR}/webserver.keytab" /etc/webserver.keytab
export KRB5_KTNAME=/etc/webserver.keytab
log "Keytab listo."

log "Esperando certificado TLS del webserver..."
while [ ! -f "/etc/fis-ca/webserver.crt" ] || [ ! -f "/etc/fis-ca/webserver.key" ]; do
    sleep 2
done
log "Certificado TLS listo."

log "Iniciando servicio web en 0.0.0.0:8443..."
exec python3 /app/app.py