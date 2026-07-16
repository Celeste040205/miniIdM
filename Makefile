# Comandos para gestionar la infraestructura de contenedores

.PHONY: up down logs shell-idm1 status help

# Levantar los servicios en segundo plano
up:
	docker-compose up -d

# Detener y eliminar los contenedores
down:
	docker-compose down

# Ver los logs en tiempo real para depuración
logs:
	docker-compose logs -f idm1

# Acceder rápidamente a la terminal del contenedor principal
shell-idm1:
	docker exec -it idm1 bash

# Verificar el estado de los contenedores
status:
	docker-compose ps

# Ayuda rápida
help:
	@echo "Comandos disponibles:"
	@echo "  make up         - Inicia la infraestructura (docker-compose up)"
	@echo "  make down       - Detiene y limpia los contenedores"
	@echo "  make logs       - Muestra los logs de idm1"
	@echo "  make shell-idm1 - Accede a la terminal bash de idm1"
	@echo "  make status     - Muestra el estado actual"