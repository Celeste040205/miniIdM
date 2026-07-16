#!/bin/bash

set -euo pipefail

FQDN="${FQDN:-idm1.fis.epn.ec}"
REALM="${REALM:-FIS.EPN.EC}"
LDAP_BASE_DN="${LDAP_BASE_DN:-dc=fis,dc=epn,dc=ec}"
LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD:-adminpassword}"
KRB5_ADMIN_PASSWORD="${KRB5_ADMIN_PASSWORD:-admin}"
KRB5_USER_DEFAULT_PASSWORD="${KRB5_USER_DEFAULT_PASSWORD:-user123}"

LDAP_MARKER="/var/lib/ldap/.initialized"
KRB5_MARKER="/var/lib/krb5kdc/.initialized"

log() { echo "[entrypoint] $*"; }

log "Escribiendo /etc/krb5.conf para el realm ${REALM}..."
cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = ${REALM}
    dns_lookup_realm = false
    dns_lookup_kdc = false
    ticket_lifetime = 24h
    renew_lifetime = 7d
    forwardable = true
    rdns = false

[realms]
    ${REALM} = {
        kdc = ${FQDN}
        admin_server = ${FQDN}
    }

[domain_realm]
    .$(echo "${FQDN#*.}") = ${REALM}
    $(echo "${FQDN#*.}") = ${REALM}
EOF

mkdir -p /etc/krb5kdc /var/lib/krb5kdc
cat > /etc/krb5kdc/kdc.conf <<EOF
[kdcdefaults]
    kdc_ports = 88
    kdc_tcp_ports = 88

[realms]
    ${REALM} = {
        database_name = /var/lib/krb5kdc/principal
        admin_keytab = /var/lib/krb5kdc/kadm5.keytab
        acl_file = /etc/krb5kdc/kadm5.acl
        key_stash_file = /var/lib/krb5kdc/stash
        max_life = 10h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
        master_key_type = aes256-cts
        supported_enctypes = aes256-cts:normal aes128-cts:normal
    }
EOF

cat > /etc/krb5kdc/kadm5.acl <<EOF
*/admin@${REALM} *
EOF

if [ ! -f "${KRB5_MARKER}" ]; then
    log "Inicializando base de datos de Kerberos (primera vez)..."
    kdb5_util create -s -r "${REALM}" -P "${KRB5_ADMIN_PASSWORD}"

    log "Creando principal de administracion admin/admin@${REALM}..."
    kadmin.local -q "addprinc -pw ${KRB5_ADMIN_PASSWORD} admin/admin@${REALM}"

    log "Creando principal de servicio para el KDC (host)..."
    kadmin.local -q "addprinc -randkey host/${FQDN}@${REALM}" || true

    log "Creando usuario de prueba testuser@${REALM}..."
    kadmin.local -q "addprinc -pw ${KRB5_USER_DEFAULT_PASSWORD} testuser@${REALM}" || true

    touch "${KRB5_MARKER}"
    log "Kerberos inicializado correctamente."
else
    log "Base de datos de Kerberos ya inicializada, se omite kdb5_util create."
fi

if [ ! -f "${LDAP_MARKER}" ]; then
    log "Inicializando OpenLDAP (primera vez) con base ${LDAP_BASE_DN}..."
    DOMAIN=$(echo "${LDAP_BASE_DN}" | sed -e 's/dc=//g' -e 's/,/./g')
    ORG=$(echo "${DOMAIN}" | cut -d. -f1 | tr '[:lower:]' '[:upper:]')

    debconf-set-selections <<EOF
slapd slapd/internal/generated_adminpw password ${LDAP_ADMIN_PASSWORD}
slapd slapd/internal/adminpw password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password2 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/password1 password ${LDAP_ADMIN_PASSWORD}
slapd slapd/domain string ${DOMAIN}
slapd shared/organization string ${ORG}
slapd slapd/backend select MDB
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/allow_ldap_v2 boolean false
slapd slapd/no_configuration boolean false
EOF

    dpkg-reconfigure -f noninteractive slapd

    touch "${LDAP_MARKER}"
    log "OpenLDAP inicializado correctamente."
else
    log "OpenLDAP ya inicializado, se omite dpkg-reconfigure."
fi

log "Arrancando supervisord..."
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
