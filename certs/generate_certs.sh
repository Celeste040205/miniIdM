#!/bin/bash
set -e

echo "INICIO DE GENERACIÓN DE CERTIFICADOS ECDSA PARA FIS.EPN.EC"

# 1. Crear la Autoridad de Certificación (CA) Raíz
echo "1. Generando clave privada y certificado de la CA Raíz..."
openssl ecparam -name prime256v1 -genkey -noout -out certs/ca.key
openssl req -new -x509 -days 3650 -key certs/ca.key -out certs/ca.crt \
    -subj "/C=EC/O=FIS EPN/CN=Autoridad Certificadora Raiz FIS"

# Función interna para generar un certificado firmado por CA
generate_cert() {
    local name=$1
    local common_name=$2
    
    echo "Generando certificado para: $common_name ($name)"
    
    # Generar llave privada ECDSA
    openssl ecparam -name prime256v1 -genkey -noout -out certs/${name}.key
    # Generar CSR
    openssl req -new -key certs/${name}.key -out certs/${name}.csr \
        -subj "/C=EC/O=FIS EPN/CN=${common_name}"
        
    # Crear archivo de extensiones para soportar nombres de dominio (SAN)
    cat <<EOF > certs/${name}.ext
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
subjectAltName = DNS:${common_name}, DNS:localhost, IP:127.0.0.1
EOF

    # Firmar el certificado con nuestra CA Raíz
    openssl x509 -req -in certs/${name}.csr -CA certs/ca.crt -CAkey certs/ca.key \
        -CAcreateserial -out certs/${name}.crt -days 365 -extfile certs/${name}.ext
        
    # Limpiar archivo temporal de extensión y CSR
    rm certs/${name}.ext certs/${name}.csr
}

# 2. Generar certificados específicos para LDAP, Kerberos y Aplicación Web
generate_cert "ldap-master" "ldap-master"
generate_cert "ldap-replica" "ldap-replica"
generate_cert "haproxy" "ldap.fis.epn.edu.ec"
generate_cert "webserver" "web.fis.epn.edu.ec"

echo "¡Certificados ECDSA creados exitosamente!"