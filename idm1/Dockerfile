FROM debian:bullseye-slim

# Evita que el instalador pida datos de forma interactiva
ENV DEBIAN_FRONTEND=noninteractive

# Preseed minimo para que la instalacion de los paquetes no se quede
# esperando input. La configuracion REAL (realm, base DN, passwords)
# se hace en runtime dentro de entrypoint.sh, usando las variables de
# entorno del .env, para no tener que reconstruir la imagen si cambian.
RUN apt-get update && \
    apt-get install -y debconf-utils && \
    echo "slapd slapd/admin_password password adminpassword" | debconf-set-selections && \
    echo "slapd slapd/root_password password adminpassword" | debconf-set-selections && \
    echo "krb5-config krb5-config/default_realm string FIS.EPN.EC" | debconf-set-selections && \
    apt-get install -y --no-install-recommends \
        slapd \
        ldap-utils \
        krb5-kdc \
        krb5-admin-server \
        libsasl2-modules-gssapi-mit \
        supervisor \
        openssl \
        procps && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Directorios de trabajo / logs de supervisor
RUN mkdir -p /var/log/supervisor /etc/krb5kdc /var/lib/krb5kdc

# Copiamos la configuracion de supervisord y el entrypoint
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Exponemos puertos clave
# 389 LDAP, 636 LDAPS, 88 Kerberos (KDC), 464 kpasswd, 749 kadmind
EXPOSE 389 636 88 464 749

WORKDIR /root

ENTRYPOINT ["/entrypoint.sh"]