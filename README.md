# Proyecto Mini-IdM: Infraestructura de Identidad Segura para la FIS

Infraestructura de autenticación y directorio para la FIS, con alta disponibilidad,
PKI propia y un servicio web protegido con Kerberos. Implementado con Docker Compose.

## Estructura del Proyecto

```text
mini-idm/
├── ca/                 # Autoridad Certificadora Raiz (PKI, ECDSA prime256v1)
│   ├── Dockerfile
│   └── entrypoint.sh   # Genera CA raiz y certifica idm1, idm2 y webserver
├── idm1/                # Imagen unica para LDAP + Kerberos (rol via NODE_ROLE)
│   ├── Dockerfile
│   ├── entrypoint.sh    # Configura slapd, KDC, TLS, SASL/GSSAPI, syncrepl/syncprov,
│   │                     # kprop/kpropd, cn=Monitor y usuarios/grupos
│   └── supervisord.conf # Plantilla base (se regenera dinamicamente en entrypoint.sh)
├── web/                 # Servicio web protegido con TLS + Kerberos (SPNEGO)
│   ├── Dockerfile
│   ├── app.py
│   └── entrypoint.sh
├── monitor/              # Exportador Prometheus personalizado (LDAP queries/seg,
│   │                      # retraso de replicacion, estado de nodos)
│   ├── Dockerfile
│   └── exporter.py
│   └── prometheus.yml    # Configuracion de scraping (cadvisor + ldap_exporter)
├── lb/
│   └── haproxy.cfg        # Balanceador LDAP/LDAPS con failover idm1 -> idm2
├── scripts/                # Pruebas de HA e inyeccion de fallos
│   ├── test_replication.sh
│   ├── test_kdc_failover.sh
│   ├── test_loadbalancer_failover.sh
│   └── fault_injection.sh
├── .env                      # Variables de entorno (realm, base DN, passwords)
├── docker-compose.yml         # Orquestacion de todos los servicios
├── Makefile                    # Comandos de gestion rapida
└── README.md
```

> Nota: `idm2` reutiliza la misma imagen que `idm1` (`build: ./idm1`); el rol
> (master/replica) se define en runtime con la variable `NODE_ROLE`.

## 1. Componentes desplegados

| Servicio | Rol | Puertos expuestos |
| --- | --- | --- |
| `ca1` | Autoridad Certificadora Raiz (PKI, ECDSA) | — (interno, volumen `ca-data`) |
| `idm1` | LDAP Master + KDC primario | 88 (Kerberos), 749 (kadmind) |
| `idm2` | LDAP Replica + KDC secundario (HA) | 1088 (Kerberos), 754 (kpropd) |
| `lb1` | HAProxy — balanceo LDAP/LDAPS con failover | 389 (LDAP), 636 (LDAPS) |
| `web1` | Servicio web con TLS + autenticacion Kerberos (SPNEGO) | 8443 (HTTPS) |
| `ldap_exporter` | Exportador Prometheus (metricas LDAP) | 9200 |
| `cadvisor` | Metricas de CPU/RAM por contenedor | 8080 |
| `prometheus` | Recoleccion de metricas | 9090 |
| `grafana` | Dashboards de monitoreo | 3000 |

## 2. Uso del Proyecto (Operatividad)

Comandos disponibles desde la raiz del proyecto (via `Makefile`):

| Comando | Accion |
| --- | --- |
| `make up` | Despliega toda la infraestructura en segundo plano |
| `make down` | Detiene y elimina los contenedores, limpiando el entorno |
| `make status` | Verifica el estado actual de los contenedores |
| `make logs` | Muestra los logs en tiempo real de `idm1` |
| `make logs-all` | Muestra los logs de todos los servicios |
| `make shell-idm1` | Accede a la terminal del contenedor `idm1` |
| `make shell-idm2` | Accede a la terminal del contenedor `idm2` |
| `make shell-web` | Accede a la terminal del contenedor `web1` |
| `make kinit-test USER=jperez` | Obtiene un ticket Kerberos de prueba para un usuario |
| `make test-web` | Prueba el servicio web protegido con Kerberos |
| `make test-replication` | Corre la prueba de replicacion LDAP (`scripts/test_replication.sh`) |
| `make test-kdc-failover` | Corre la prueba de failover del KDC |
| `make test-lb-failover` | Corre la prueba de failover del balanceador de carga |
| `make fault-injection` | Corre la suite de inyeccion de fallos |
| `make test-all` | Corre todas las pruebas de HA en orden |
| `make monitoring-up` | Abre accesos rapidos a Prometheus y Grafana (URLs) |
| `make clean` | Detiene contenedores y elimina volumenes (borra todo el estado) |

## 3. Arquitectura Tecnica

* **PKI**: `ca1` genera una CA raiz ECDSA (curva `prime256v1`) y emite certificados
  para `idm1`, `idm2` y `webserver.fis.epn.ec`, montados via el volumen compartido `ca-data`.
* **LDAP**: OpenLDAP en `idm1` (master) e `idm2` (replica), DIT raiz `dc=fis,dc=epn,dc=ec`,
  replicacion via `syncprov`/`syncrepl` sobre LDAPS, backend `cn=Monitor` habilitado
  para metricas.
* **Kerberos**: MIT Kerberos, realm `FIS.EPN.EC`. `idm1` es KDC primario, `idm2` es
  KDC secundario sincronizado por `kprop`/`kpropd`. Principals de usuario
  (`jperez`, `malvan`, `dnoboa`, `testuser`) y de servicio (`host/`, `ldap/`, `HTTP/webserver`).
* **Integracion LDAP-Kerberos**: autenticacion SASL/GSSAPI en `slapd`, con
  `olcAuthzRegexp` mapeando la identidad Kerberos a la entrada LDAP correspondiente
  en `ou=people`.
* **Servicio Web protegido**: `web1` sirve HTTPS con el certificado de la CA FIS y
  exige un ticket Kerberos (SPNEGO/Negotiate) para responder — flujo
  `Browser -> Kerberos Ticket -> Web Service`.
* **Alta disponibilidad**:
  - LDAP: replica en caliente (`idm2`), lecturas continuan si `idm1` cae.
  - Kerberos: KDC secundario con base de datos propagada periodicamente.
  - Balanceo de carga: HAProxy expone `ldap.fis.epn.ec` con `idm2` como backend
    de respaldo (`backup`), activo automaticamente si `idm1` falla.
* **Monitoreo**: Prometheus recolecta metricas de `cadvisor` (CPU/RAM por
  contenedor) y del exportador propio `ldap_exporter` (queries/seg, retraso de
  replicacion, disponibilidad de nodos). Grafana visualiza los dashboards.

## 4. Flujo de autenticacion

1. El usuario obtiene un TGT del KDC (`idm1` o `idm2` en caso de failover).
2. Solicita un ticket de servicio para `HTTP/webserver.fis.epn.ec` o `ldap/idm1.fis.epn.ec`.
3. El servicio (web o LDAP) valida el ticket via GSSAPI/SASL.
4. La autorizacion final se resuelve consultando el atributo correspondiente
   en el DIT de LDAP (`ou=people,dc=fis,dc=epn,dc=ec`).
5. Todo el trafico LDAP y HTTP viaja cifrado con certificados emitidos por la
   CA raiz de la FIS.

## 5. Pruebas de Alta Disponibilidad

Ver `scripts/`. Cada script imprime los tiempos medidos (latencia de failover,
tiempo de recuperacion) que se documentan en el informe final. Resumen de
experimentos cubiertos (ver tabla del enunciado):

| Experimento | Script | Metrica |
| --- | --- | --- |
| Replicacion LDAP | `scripts/test_replication.sh` | Retraso de propagacion |
| Failover del KDC | `scripts/test_kdc_failover.sh` | Latencia de autenticacion |
| Balanceo de carga | `scripts/test_loadbalancer_failover.sh` | Disponibilidad / throughput |
| Inyeccion de fallos | `scripts/fault_injection.sh` | Tiempo de recuperacion |

## 6. Evidencias

* **Certificados**: emitidos en runtime por `ca1`, verificables con
  `openssl s_client -connect idm1.fis.epn.ec:636 -CAfile ca.crt`.
* **Autenticacion**: capturas en `/evidencia` mostrando obtencion de tickets
  (`kinit`) y acceso exitoso al servicio web protegido.
* **Metricas**: dashboards de Grafana (`http://localhost:3000`) con retraso
  de replicacion, queries/seg y uso de CPU/RAM.
