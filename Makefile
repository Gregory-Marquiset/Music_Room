
COMPOSE := docker compose --env-file .env -f docker-compose.yml

.DEFAULT_GOAL := help
.PHONY: help build up down test

help:
	@echo ""
	@echo "Commande disponible: "
	@echo "make help		- Affiche cette aide"
	@echo "make build		- Build les images"
	@echo "make up			- Build puis demarre les service (detach)"
	@echo "make down		- Down"
	@echo "make test		- Test"
	@echo ""

build:
	$(COMPOSE) build

up: build
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

test:
