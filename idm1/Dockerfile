FROM debian:bullseye-slim

# Evita que el instalador pida datos de forma interactiva
ENV DEBIAN_FRONTEND=noninteractive

# Instalamos dependencias y configuramos las contraseñas antes de instalar
RUN apt-get update && \
    apt-get install -y debconf-utils && \
    echo "slapd slapd/admin_password password adminpassword" | debconf-set-selections && \
    echo "slapd slapd/root_password password adminpassword" | debconf-set-selections && \
    apt-get install -y slapd krb5-kdc krb5-admin-server openssl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Exponemos puertos clave
EXPOSE 389 636 88 464

# Directorio de trabajo
WORKDIR /root

# Mantenemos el contenedor vivo (esto lo cambiaremos después por el comando real de arranque)
CMD ["sleep", "infinity"]