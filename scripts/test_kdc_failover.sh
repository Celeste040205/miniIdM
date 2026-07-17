#!/bin/bash
set -e
export KRB5_CONFIG=/etc/krb5.conf

echo ">> Obteniendo ticket del KDC primario (idm1)..."
START=$(date +%s.%N)
docker exec idm1 kinit -k -t /etc/krb5.keytab host/idm1.fis.epn.ec@FIS.EPN.EC
END=$(date +%s.%N)
echo ">> OK. Latencia primario: $(echo "$END - $START" | bc)s"

echo ">> Deteniendo krb5kdc en idm1..."
docker exec idm1 supervisorctl stop krb5kdc

echo ">> Solicitando ticket contra el KDC secundario (idm2)..."
START=$(date +%s.%N)
docker exec idm2 kinit -k -t /etc/krb5.keytab host/idm2.fis.epn.ec@FIS.EPN.EC
END=$(date +%s.%N)
echo ">> OK. Latencia de failover: $(echo "$END - $START" | bc)s"

echo ">> Restaurando krb5kdc en idm1..."
docker exec idm1 supervisorctl start krb5kdc