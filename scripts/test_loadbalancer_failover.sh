#!/bin/bash
set -e
echo ">> Probando LDAP a traves del balanceador (esperado: idm1 activo)..."
ldapsearch -x -H ldap://localhost:389 -b "dc=fis,dc=epn,dc=ec" -D "cn=admin,dc=fis,dc=epn,dc=ec" -w adminpassword "(objectClass=*)" > /dev/null && echo "OK"

echo ">> Deteniendo slapd en idm1 (backend primario del LB)..."
docker exec idm1 supervisorctl stop slapd

sleep 3
echo ">> Verificando que el servicio LDAP sigue disponible via HAProxy (failover a idm2)..."
ldapsearch -x -H ldap://localhost:389 -b "dc=fis,dc=epn,dc=ec" -D "cn=admin,dc=fis,dc=epn,dc=ec" -w adminpassword "(objectClass=*)" > /dev/null && echo "OK: servicio disponible via idm2 (backup)"

echo ">> Restaurando idm1..."
docker exec idm1 supervisorctl start slapd