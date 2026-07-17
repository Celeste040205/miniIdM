# Comandos para gestionar la infraestructura de identidad de la FIS

.PHONY: up down logs logs-all shell-idm1 shell-idm2 shell-web status \
        kinit-test test-web test-replication test-kdc-failover \
        test-lb-failover fault-injection test-all monitoring-up clean help

# --- Ciclo de vida de la infraestructura ---

# Levantar todos los servicios en segundo plano
up:
	docker-compose up -d --build

# Detener y eliminar los contenedores (conserva los volumenes/datos)
down:
	docker-compose down

# Detener contenedores y eliminar TODOS los volumenes (reinicio limpio total)
clean:
	docker-compose down -v

# Verificar el estado de los contenedores
status:
	docker-compose ps

# --- Logs ---

# Ver los logs en tiempo real de idm1 (LDAP master + KDC primario)
logs:
	docker-compose logs -f idm1

# Ver los logs de todos los servicios
logs-all:
	docker-compose logs -f

# --- Acceso a contenedores ---

shell-idm1:
	docker exec -it idm1 bash

shell-idm2:
	docker exec -it idm2 bash

shell-web:
	docker exec -it web1 bash

# --- Pruebas funcionales ---

# Obtiene un ticket Kerberos de prueba. Uso: make kinit-test USER=jperez
USER ?= testuser
kinit-test:
	docker exec -it idm1 kinit $(USER)@FIS.EPN.EC

# Prueba el servicio web protegido con Kerberos (requiere ticket valido)
test-web:
	docker exec -it idm1 bash -c "kinit -k -t /etc/krb5.keytab host/idm1.fis.epn.ec@FIS.EPN.EC 2>/dev/null; curl --negotiate -u : -k https://webserver.fis.epn.ec:8443/"

# --- Pruebas de Alta Disponibilidad / Inyeccion de fallos ---

test-replication:
	bash scripts/test_replication.sh

test-kdc-failover:
	bash scripts/test_kdc_failover.sh

test-lb-failover:
	bash scripts/test_loadbalancer_failover.sh

fault-injection:
	bash scripts/fault_injection.sh

# Corre toda la bateria de pruebas de HA en orden
test-all: test-replication test-kdc-failover test-lb-failover fault-injection
	@echo "Todas las pruebas de HA finalizaron."

# --- Monitoreo ---

monitoring-up:
	@echo "Prometheus:  http://localhost:9090"
	@echo "Grafana:     http://localhost:3000 (admin/admin)"
	@echo "cAdvisor:    http://localhost:8080"

# --- Ayuda ---

help:
	@echo "Comandos disponibles:"
	@echo "  make up                  - Inicia toda la infraestructura (build + up)"
	@echo "  make down                - Detiene los contenedores (conserva datos)"
	@echo "  make clean               - Detiene y borra TODOS los volumenes"
	@echo "  make status              - Muestra el estado de los contenedores"
	@echo "  make logs                - Logs de idm1"
	@echo "  make logs-all            - Logs de todos los servicios"
	@echo "  make shell-idm1          - Terminal de idm1"
	@echo "  make shell-idm2          - Terminal de idm2"
	@echo "  make shell-web           - Terminal de web1"
	@echo "  make kinit-test USER=x   - Obtiene ticket Kerberos para el usuario x"
	@echo "  make test-web            - Prueba el servicio web protegido con Kerberos"
	@echo "  make test-replication    - Prueba de replicacion LDAP"
	@echo "  make test-kdc-failover   - Prueba de failover del KDC"
	@echo "  make test-lb-failover    - Prueba de failover del balanceador de carga"
	@echo "  make fault-injection     - Suite de inyeccion de fallos"
	@echo "  make test-all            - Corre todas las pruebas de HA"
	@echo "  make monitoring-up       - Muestra las URLs de Prometheus/Grafana"