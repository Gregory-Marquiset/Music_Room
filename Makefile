
COMPOSE := docker compose --env-file .env -f docker-compose.yml

.DEFAULT_GOAL := help
.PHONY: help

help:
	@echo ""
	@echo "Commande disponible: "
	@echo "make help		- Affiche cette aide"
	@echo "make build		- Build les images"
	@echo "make up			- Build puis demarre les service (detach)"
	@echo "make down		- Down"
	@echo "make nuke		- Purge complete du projet"
	@echo ""

build:
	$(COMPOSE) build

up: build
	$(COMPOSE) up

down:
	$(COMPOSE) down

nuke: 
	@if [ -L services/frontend/node_modules ]; then rm -f services/frontend/node_modules; fi
	@echo "Pruning docker…"
	docker image prune -af
	docker system prune -af
	docker network prune -f
	docker volume prune -f
