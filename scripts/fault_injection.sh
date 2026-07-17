#!/bin/bash
set -e

echo "=== 1. Crash del servidor (kill -9 a slapd en idm1) ==="
PID=$(docker exec idm1 pidof slapd)
docker exec idm1 kill -9 "$PID"
sleep 2
echo "supervisord deberia reiniciarlo automaticamente (autorestart=true):"
docker exec idm1 supervisorctl status slapd

echo "=== 2. Particion de red (bloquear idm1 <-> idm2) ==="
docker exec idm1 sh -c "apt-get install -y iptables >/dev/null 2>&1 || true"
docker exec idm1 iptables -A OUTPUT -d idm2.fis.epn.ec -j DROP
echo "Trafico hacia idm2 bloqueado por 15s..."
sleep 15
docker exec idm1 iptables -D OUTPUT -d idm2.fis.epn.ec -j DROP
echo "Particion removida."

echo "=== 3. Certificado expirado ==="
docker exec idm1 openssl req -new -x509 -key /tmp/fake.key -out /tmp/expired.crt -days -1 \
    -subj "/CN=idm1.fis.epn.ec" 2>/dev/null || \
    echo "(genera manualmente un cert con -days -1 y reemplaza olcTLSCertificateFile para simular esto; revertir despues con ldapmodify)"

echo "=== 4. Fallo del KDC ==="
docker exec idm1 supervisorctl stop krb5kdc
sleep 5
echo "Intentando kinit (debe fallar):"
docker exec idm1 kinit -k -t /etc/krb5.keytab host/idm1.fis.epn.ec@FIS.EPN.EC || echo "Fallo esperado."
docker exec idm1 supervisorctl start krb5kdc