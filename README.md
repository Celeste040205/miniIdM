# Proyecto Mini-IdM: Infraestructura de Identidad Segura

## Estructura del Proyecto
La arquitectura del repositorio sigue una organización modular para separar las configuraciones de los servicios principales:

```text
mini-idm/
├── ca/                 # Archivos de la Autoridad Certificadora (PKI)
├── idm1/               # Configuración específica y scripts de inicialización de idm1
├── ldap/               # Configuración de OpenLDAP
│   ├── master/         # Datos y configuración del nodo maestro
│   └── replica/        # Datos y configuración para redundancia
├── kerberos/           # Archivos de configuración krb5.conf y KDC
├── certs/              # Certificados generados (incluye mgallardo.crt)
├── evidencia/          # Capturas de pantalla
├── .env                # Variables de entorno (puertos, dominios)
├── docker-compose.yml  # Orquestación de servicios
├── Makefile            # Comandos de gestión rápida
└── README.md           # Documentación del proyecto
```
## 2. Uso del Proyecto (Operatividad)

Para gestionar la infraestructura de forma eficiente, utiliza los comandos definidos en el `Makefile` desde la raíz del proyecto:

| Comando | Acción |
| --- | --- |
| `make up` | Despliega toda la infraestructura en segundo plano. |
| `make shell-idm1` | Accede a la terminal del contenedor `idm1` para administración. |
| `make status` | Verifica el estado actual de los contenedores. |
| `make logs` | Muestra los logs en tiempo real para depuración. |
| `make down` | Detiene y elimina los contenedores, limpiando el entorno. |

## 3. Arquitectura Técnica

* **Núcleo (`idm1`)**: Servidor central que unifica la persistencia de atributos mediante **OpenLDAP** y la gestión de tickets de autenticación mediante **MIT Kerberos**.
* **Seguridad**: Implementación de **PKI con ECDSA (prime256v1)** para asegurar las conexiones mediante TLS.
* **Flujo de Trabajo**:
1. El usuario se autentica contra el **KDC** (Kerberos) obteniendo un TGT.
2. La autorización se valida consultando atributos en el **DIT de LDAP**.
3. La comunicación entre nodos se cifra mediante los certificados emitidos por la **CA raíz**.

## 4. Evidencias

* **Certificados**: En la carpeta `/certs` encontrarás el certificado `mgallardo.crt` firmado por la CA.
* **Autenticación**: En `/evidencia` se encuentran los logs que demuestran la obtención exitosa de tickets mediante `kinit`.