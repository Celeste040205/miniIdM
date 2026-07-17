#!/bin/bash

set -euo pipefail

NODE_ROLE="${NODE_ROLE:-replica}"
FQDN="${FQDN:-idm2.fis.epn.ec}"
REALM="${REALM:-FIS.EPN.EC}"
LDAP_BASE_DN="${LDAP_BASE_DN:-dc=fis,dc=epn,dc=ec}"
LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD:-adminpassword}"
KRB5_ADMIN_PASSWORD="${KRB5_ADMIN_PASSWORD:-admin}"
KRB5_USER_DEFAULT_PASSWORD="${KRB5_USER_DEFAULT_PASSWORD:-user123}"

LDAP_MARKER="/var/lib/ldap/.initialized"
KRB5_MARKER="/var/lib/krb5kdc/.initialized"
KRB5_DB_FILE="/var/lib/krb5kdc/principal"
LDAP_KEYTAB="/var/lib/krb5kdc/ldap.keytab"
SHARED_DIR="/etc/krb5kdc/shared"

log() { echo "[entrypoint-${NODE_ROLE}] $*"; }

# --- ASEGURAR DEFINICIÓN DEL PUERTO DE REPLICACIÓN DE KERBEROS ---
if ! grep -q "^krb5_prop" /etc/services 2>/dev/null; then
    log "Registrando servicio krb5_prop en /etc/services..."
    echo "krb5_prop       754/tcp         # Kerberos slave propagation" >> /etc/services
fi

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
    dns_canonicalize_hostname = false
    ignore_acceptor_hostname = true

[realms]
    ${REALM} = {
        kdc = idm1.fis.epn.ec
        kdc = idm2.fis.epn.ec
        admin_server = idm1.fis.epn.ec
    }

[domain_realm]
    .$(echo "${FQDN#*.}") = ${REALM}
    $(echo "${FQDN#*.}") = ${REALM}
EOF

mkdir -p /etc/krb5kdc /var/lib/krb5kdc
chgrp openldap /var/lib/krb5kdc
chmod 750 /var/lib/krb5kdc

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

# --- CONFIGURACION DE KERBEROS SEGUN EL ROL ---

if [ "${NODE_ROLE}" = "master" ]; then
    # --- Paso 1: crear la base de datos de Kerberos solo si NO existe en disco ---
    if [ ! -f "${KRB5_DB_FILE}" ]; then
        log "Inicializando base de datos de Kerberos (primera vez)..."
        kdb5_util create -s -r "${REALM}" -P "${KRB5_ADMIN_PASSWORD}"
    else
        log "Base de datos de Kerberos ya existe en disco, se omite kdb5_util create."
    fi

    # --- Paso 2: crear los principals solo si NO se ha hecho antes (marcador) ---
    if [ ! -f "${KRB5_MARKER}" ]; then
        log "Creando principal de administracion admin/admin@${REALM}..."
        kadmin.local -q "addprinc -pw ${KRB5_ADMIN_PASSWORD} admin/admin@${REALM}" || true

        log "Creando principal de servicio para el KDC (host idm1)..."
        kadmin.local -q "addprinc -randkey host/idm1.fis.epn.ec@${REALM}" || true
        kadmin.local -q "addprinc -randkey host/idm1@${REALM}" || true
        kadmin.local -q "ktadd -k /etc/krb5.keytab host/idm1.fis.epn.ec@${REALM} host/idm1@${REALM}" || true

        log "Creando usuario de prueba testuser@${REALM}..."
        kadmin.local -q "addprinc -pw ${KRB5_USER_DEFAULT_PASSWORD} testuser@${REALM}" || true

        log "Creando principal de servicio ldap/idm1.fis.epn.ec@${REALM} y su keytab..."
        kadmin.local -q "addprinc -randkey ldap/idm1.fis.epn.ec@${REALM}" || true
        kadmin.local -q "ktadd -k ${LDAP_KEYTAB} ldap/idm1.fis.epn.ec@${REALM}" || true

        log "Creando alias corto ldap/idm1@${REALM}..."
        kadmin.local -q "addprinc -randkey ldap/idm1@${REALM}" || true
        kadmin.local -q "ktadd -k ${LDAP_KEYTAB} ldap/idm1@${REALM}" || true

        log "Creando principals y pregenerando keytab para la réplica idm2..."
        mkdir -p "${SHARED_DIR}"
        kadmin.local -q "addprinc -randkey host/idm2.fis.epn.ec@${REALM}" || true
        kadmin.local -q "addprinc -randkey host/idm2@${REALM}" || true
        kadmin.local -q "addprinc -randkey ldap/idm2.fis.epn.ec@${REALM}" || true
        kadmin.local -q "addprinc -randkey ldap/idm2@${REALM}" || true
        kadmin.local -q "ktadd -k ${SHARED_DIR}/idm2.keytab host/idm2.fis.epn.ec@${REALM} host/idm2@${REALM} ldap/idm2.fis.epn.ec@${REALM} ldap/idm2@${REALM}" || true

        chown root:openldap "${LDAP_KEYTAB}"
        chmod 640 "${LDAP_KEYTAB}"

        touch "${KRB5_MARKER}"
        log "Kerberos Master inicializado correctamente."
    else
        log "Base de datos de Kerberos ya inicializada, se omiten los addprinc."
    fi

else
    # NODE_ROLE = replica
    if [ ! -f "${KRB5_MARKER}" ]; then
        log "Esperando que el Master pregenere el keytab para la replica..."
        while [ ! -f "${SHARED_DIR}/idm2.keytab" ]; do
            sleep 2
        done
        log "Keytab de replica encontrado. Copiando..."
        cp "${SHARED_DIR}/idm2.keytab" /etc/krb5.keytab
        cp "${SHARED_DIR}/idm2.keytab" "${LDAP_KEYTAB}"
        chown root:openldap "${LDAP_KEYTAB}" /etc/krb5.keytab
        chmod 640 "${LDAP_KEYTAB}" /etc/krb5.keytab

        log "Configurando kpropd.acl para permitir propagacion desde el Master..."
        cat > /etc/krb5kdc/kpropd.acl <<EOF
host/idm1.fis.epn.ec@${REALM}
host/idm1@${REALM}
EOF

        # Crear una base de datos Kerberos local vacia necesaria para que kpropd arranque
        kdb5_util create -s -r "${REALM}" -P "${KRB5_ADMIN_PASSWORD}"

        touch "${KRB5_MARKER}"
        log "Kerberos Replica configurado."
    fi
fi

# --- CONFIGURACION DE OPENLDAP ---

if [ ! -f "${LDAP_MARKER}" ] || [ ! -d "/etc/ldap/slapd.d/cn=config" ]; then
    log "Inicializando OpenLDAP (primera vez o configuracion ausente) con base ${LDAP_BASE_DN}..."
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

log "Esperando a que la CA local genere los certificados TLS en disco..."
SHORT_NAME="${FQDN%%.*}"
while [ ! -f "/etc/fis-ca/ca.crt" ] || [ ! -f "/etc/fis-ca/${SHORT_NAME}.crt" ] || [ ! -f "/etc/fis-ca/${SHORT_NAME}.key" ]; do
    sleep 2
done
log "Certificados TLS listos en disco."

log "Configurando cliente LDAP para confiar en la CA local..."
if ! grep -q "^TLS_CACERT" /etc/ldap/ldap.conf 2>/dev/null; then
    echo "TLS_CACERT /etc/fis-ca/ca.crt" >> /etc/ldap/ldap.conf
fi

# --- Configurar TLS (LDAPS) en slapd, solo la primera vez ---
TLS_MARKER="/var/lib/ldap/.tls_configured"
SHORT_NAME="${FQDN%%.*}"
if [ ! -f "${TLS_MARKER}" ]; then
    log "Configurando TLS en slapd..."

    /usr/sbin/slapd -h "ldapi:///" -u openldap -g openldap
    sleep 2

    cat > /tmp/tls.ldif <<EOF
dn: cn=config
changetype: modify
add: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/fis-ca/ca.crt
-
add: olcTLSCertificateFile
olcTLSCertificateFile: /etc/fis-ca/${SHORT_NAME}.crt
-
add: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/fis-ca/${SHORT_NAME}.key
EOF

    ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/tls.ldif

    pkill -x slapd
    sleep 2

    touch "${TLS_MARKER}"
    log "TLS configurado correctamente."
else
    log "TLS ya configurado, se omite."
fi

# --- Configurar SASL/GSSAPI en slapd, solo la primera vez ---
SASL_MARKER="/var/lib/ldap/.sasl_configured"
if [ ! -f "${SASL_MARKER}" ]; then
    log "Configurando SASL (GSSAPI) en slapd (quedando olcSaslHost deshabilitado)..."

    /usr/sbin/slapd -h "ldapi:///" -u openldap -g openldap
    sleep 2

    cat > /tmp/sasl.ldif <<EOF
dn: cn=config
changetype: modify
add: olcSaslRealm
olcSaslRealm: ${REALM}
EOF

    ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/sasl.ldif

    pkill -x slapd
    sleep 2

    touch "${SASL_MARKER}"
    log "SASL/GSSAPI configurado correctamente."
else
    log "SASL/GSSAPI ya configurado, se omite."
fi

# --- CONFIGURACION DE REPLICACION OPENLDAP ---

if [ "${NODE_ROLE}" = "master" ]; then
    SYNCPROV_MARKER="/var/lib/ldap/.syncprov_configured"
    if [ ! -f "${SYNCPROV_MARKER}" ]; then
        log "Habilitando syncprov en Master..."
        /usr/sbin/slapd -h "ldapi:///" -u openldap -g openldap
        sleep 2

        cat > /tmp/syncprov_load.ldif <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov.la
EOF
        ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/syncprov_load.ldif

        cat > /tmp/syncprov_overlay.ldif <<EOF
dn: olcOverlay=syncprov,olcDatabase={1}mdb,cn=config
changetype: add
objectClass: olcOverlayConfig
objectClass: olcSyncProvConfig
olcOverlay: syncprov
olcSpCheckpoint: 100 10
EOF
        ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/syncprov_overlay.ldif

        pkill -x slapd
        sleep 2
        touch "${SYNCPROV_MARKER}"
        log "syncprov habilitado correctamente."
    fi

    # --- Crear arbol de usuarios y mapeo GSSAPI en LDAP ---
    POPULATE_MARKER="/var/lib/ldap/.populated"
    if [ ! -f "${POPULATE_MARKER}" ]; then
        log "Creando arbol de usuarios y mapeo GSSAPI en LDAP..."
        /usr/sbin/slapd -h "ldapi:///" -u openldap -g openldap
        sleep 2

        cat > /tmp/populate.ldif <<EOF
dn: ou=people,${LDAP_BASE_DN}
objectClass: organizationalUnit
ou: people

dn: uid=testuser,ou=people,${LDAP_BASE_DN}
objectClass: inetOrgPerson
cn: Test User
sn: User
uid: testuser
userPassword: ${KRB5_USER_DEFAULT_PASSWORD}
mail: testuser@fis.epn.ec
EOF
        ldapadd -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PASSWORD}" -H ldapi:/// -f /tmp/populate.ldif

        cat > /tmp/authz.ldif <<EOF
dn: cn=config
changetype: modify
add: olcAuthzRegexp
olcAuthzRegexp: "uid=([^,]+),cn=([^,]+),cn=gssapi,cn=auth" "uid=\$1,ou=people,${LDAP_BASE_DN}"
EOF
        ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/authz.ldif

        pkill -x slapd
        sleep 2
        touch "${POPULATE_MARKER}"
        log "Arbol de usuarios y mapeo GSSAPI configurados y verificados correctamente."
    fi

else
    # NODE_ROLE = replica
    SYNCREPL_MARKER="/var/lib/ldap/.syncrepl_configured"
    if [ ! -f "${SYNCREPL_MARKER}" ]; then
        log "Configurando syncrepl en la Replica..."
        /usr/sbin/slapd -h "ldapi:///" -u openldap -g openldap
        sleep 2

        cat > /tmp/syncrepl.ldif <<EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: entryUUID eq
-
add: olcDbIndex
olcDbIndex: entryCSN eq
-
add: olcSyncrepl
olcSyncrepl: rid=001
  provider=ldaps://idm1.fis.epn.ec:636
  type=refreshAndPersist
  interval=00:00:00:10
  searchbase="${LDAP_BASE_DN}"
  binddn="cn=admin,${LDAP_BASE_DN}"
  credentials="${LDAP_ADMIN_PASSWORD}"
  bindmethod=simple
  starttls=no
  tls_cacert=/etc/fis-ca/ca.crt
  tls_reqcert=allow
-
add: olcUpdateRef
olcUpdateRef: ldaps://idm1.fis.epn.ec:636
EOF
        ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/syncrepl.ldif

        # Tambien agregar el mapeo AuthzRegexp localmente en la replica para que
        # resuelva las identidades GSSAPI que se autentiquen contra ella
        cat > /tmp/authz_replica.ldif <<EOF
dn: cn=config
changetype: modify
add: olcAuthzRegexp
olcAuthzRegexp: "uid=([^,]+),cn=([^,]+),cn=gssapi,cn=auth" "uid=\$1,ou=people,${LDAP_BASE_DN}"
EOF
        ldapmodify -Y EXTERNAL -H ldapi:/// -f /tmp/authz_replica.ldif

        pkill -x slapd
        sleep 2
        touch "${SYNCREPL_MARKER}"
        log "syncrepl y authz configurados en Replica."
    fi
fi

# --- GENERACION DINAMICA DE CONFIGURACION DE SUPERVISORD ---

log "Escribiendo configuracion de supervisord..."

if [ "${NODE_ROLE}" = "master" ]; then
    cat > /etc/supervisor/supervisord.conf <<EOF
[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:slapd]
command=/usr/sbin/slapd -d 0 -h "ldap:/// ldapi:/// ldaps:///" -u openldap -g openldap
environment=KRB5_KTNAME="/var/lib/krb5kdc/ldap.keytab"
autostart=true
autorestart=true
startsecs=3
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:krb5kdc]
command=/usr/sbin/krb5kdc -n
autostart=true
autorestart=true
startsecs=3
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:kadmind]
command=/usr/sbin/kadmind -nofork
autostart=true
autorestart=true
startsecs=3
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:kprop_sync]
command=/usr/local/bin/kprop_sync.sh
autostart=true
autorestart=true
startsecs=5
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF

    # Escribir el script de sincronizacion automatica de Kerberos
    cat > /usr/local/bin/kprop_sync.sh <<'EOF'
#!/bin/bash
set -euo pipefail
log() { echo "[kprop-sync] $*"; }

log "Iniciando script de propagacion Kerberos en segundo plano..."
while ! nc -z idm2.fis.epn.ec 754 2>/dev/null; do
    log "Esperando a que idm2 (kpropd) este listo en el puerto 754..."
    sleep 5
done

log "idm2 listo. Iniciando propagacion periodica..."
while true; do
    log "Realizando dump de la base de datos de Kerberos..."
    kdb5_util dump /var/lib/krb5kdc/replica_dump
    log "Propagando base de datos a idm2.fis.epn.ec..."
    if kprop -f /var/lib/krb5kdc/replica_dump idm2.fis.epn.ec; then
        log "Propagacion exitosa."
    else
        log "Error en la propagacion."
    fi
    sleep 30
done
EOF
    chmod +x /usr/local/bin/kprop_sync.sh

else
    # NODE_ROLE = replica
    cat > /etc/supervisor/supervisord.conf <<EOF
[unix_http_server]
file=/var/run/supervisor.sock
chmod=0700

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock

[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:slapd]
command=/usr/sbin/slapd -d 0 -h "ldap:/// ldapi:/// ldaps:///" -u openldap -g openldap
environment=KRB5_KTNAME="/var/lib/krb5kdc/ldap.keytab"
autostart=true
autorestart=true
startsecs=3
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:krb5kdc]
command=/usr/sbin/krb5kdc -n
autostart=true
autorestart=true
startsecs=3
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:kpropd]
command=/usr/sbin/kpropd -S -d
autostart=true
autorestart=true
startsecs=3
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF
fi

log "Arrancando supervisord..."
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf