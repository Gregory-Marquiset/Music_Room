
COMPOSE := docker compose --env-file .env -f docker-compose.yml
UV_IMAGE := ghcr.io/astral-sh/uv:0.12.23-python3.13-trixie-slim

POSTGRES_PASSWORD := secrets/postgres_password
REDIS_PASSWORD := secrets/redis_password
DJANGO_SECRET_KEY := secrets/django_secret_key

.DEFAULT_GOAL := help
.PHONY: help secrets deps build up down test

help:
	@echo ""
	@echo "Commande disponible: "
	@echo "make help		- Affiche cette aide"
	@echo "make deps		- Regenere requirements.txt depuis requirements.in"
	@echo "make secrets		- Genere les secrets"
	@echo "make build		- Build les images"
	@echo "make up			- Build puis demarre les service (detach)"
	@echo "make down		- Down"
	@echo "make test		- Test"
	@echo ""

deps:
	MSYS_NO_PATHCONV=1 docker run --rm \
		--user "$$(id -u):$$(id -g)" \
		-e UV_CACHE_DIR=/tmp/uv-cache \
		-v ./backend:/src -w /src \
		$(UV_IMAGE) \
		uv pip compile requirements.in -o requirements.txt

secrets:
	@mkdir -p secrets
	@if [ ! -s "$(POSTGRES_PASSWORD)" ]; then \
		od -An -tx1 -N32 /dev/urandom | tr -d ' \n' > "$(POSTGRES_PASSWORD)"; \
	fi
	@if [ ! -s "$(REDIS_PASSWORD)" ]; then \
		od -An -tx1 -N32 /dev/urandom | tr -d ' \n' > "$(REDIS_PASSWORD)"; \
	fi
	@if [ ! -s "$(DJANGO_SECRET_KEY)" ]; then \
		od -An -tx1 -N32 /dev/urandom | tr -d ' \n' > "$(DJANGO_SECRET_KEY)"; \
	fi

build:
	$(COMPOSE) build

up: secrets build
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

test:
