#!/bin/bash
set -e
BASE="dc=fis,dc=epn,dc=ec"
echo ">> Agregando usuario de prueba en el master (idm1)..."
docker exec idm1 bash -c "cat > /tmp/repltest.ldif <<EOF
dn: uid=repltest,ou=people,${BASE}
objectClass: inetOrgPerson
cn: Repl Test
sn: Test
uid: repltest
userPassword: test123
EOF
ldapadd -x -D cn=admin,${BASE} -w adminpassword -H ldapi:/// -f /tmp/repltest.ldif"

echo ">> Esperando 5s de propagacion..."
sleep 5

echo ">> Verificando en la replica (idm2)..."
docker exec idm2 ldapsearch -x -D cn=admin,${BASE} -w adminpassword -H ldapi:/// -b "${BASE}" "(uid=repltest)"

echo ">> Deteniendo el master..."
START=$(date +%s.%N)
docker exec idm1 supervisorctl stop slapd

echo ">> Probando lectura contra la replica mientras el master esta caido..."
docker exec idm2 ldapsearch -x -H ldap://idm2.fis.epn.ec:389 -b "${BASE}" "(uid=repltest)"
END=$(date +%s.%N)
echo ">> Lectura exitosa. Tiempo total: $(echo "$END - $START" | bc) s"

echo ">> Restaurando master..."
docker exec idm1 supervisorctl start slapd