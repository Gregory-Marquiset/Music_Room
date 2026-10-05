
COMPOSE := docker compose --env-file .env -f docker-compose.yml

POSTGRES_PASSWORD := secrets/postgres_password
REDIS_PASSWORD := secrets/redis_password

.DEFAULT_GOAL := help
.PHONY: help secrets build up down test

help:
	@echo ""
	@echo "Commande disponible: "
	@echo "make help		- Affiche cette aide"
	@echo "make secrets		- Genere les secrets"
	@echo "make build		- Build les images"
	@echo "make up			- Build puis demarre les service (detach)"
	@echo "make down		- Down"
	@echo "make test		- Test"
	@echo ""

secrets:
	@mkdir -p secrets
	@if [ ! -s "$(POSTGRES_PASSWORD)" ]; then \
		od -An -tx1 -N32 /dev/urandom | tr -d ' \n' > "$(POSTGRES_PASSWORD)"; \
	fi
	@if [ ! -s "$(REDIS_PASSWORD)" ]; then \
		od -An -tx1 -N32 /dev/urandom | tr -d ' \n' > "$(REDIS_PASSWORD)"; \
	fi

build:
	$(COMPOSE) build

up: secrets build
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

test:
