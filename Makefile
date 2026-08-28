# One-command entry points for local development.
#
# Run `make` or `make help` to see everything available.
# First time on a new machine: see the Setup section in README.md.

API := api
WEB := web
DB_CONTAINER := motorcycle-pos-mysql

.DEFAULT_GOAL := help
.PHONY: help setup require-docker db-up db-down db-reset db-shell dev-api dev-web test test-api test-web lint

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

setup: ## Bootstrap everything on a fresh clone (database, deps, app key, migrations)
	@$(MAKE) require-docker
	@echo "==> Checking Node version against $(WEB)/.nvmrc"
	@want=$$(tr -d 'v \n' < $(WEB)/.nvmrc); \
	have=$$(node -v 2>/dev/null | sed 's/v//; s/\..*//'); \
	if [ "$$have" != "$$want" ]; then \
		echo "Node $$want expected, found $${have:-none}. Run: nvm install && nvm use"; \
		exit 1; \
	fi
	@$(MAKE) db-up
	@echo "==> Installing API dependencies"
	@cd $(API) && composer install --no-interaction
	@if [ ! -f $(API)/.env ]; then \
		echo "==> Creating $(API)/.env from .env.example"; \
		cp $(API)/.env.example $(API)/.env; \
	fi
	@grep -q '^APP_KEY=base64:' $(API)/.env || { \
		echo "==> Generating application key"; \
		cd $(API) && php artisan key:generate; \
	}
	@echo "==> Running migrations"
	@cd $(API) && php artisan migrate
	@echo "==> Installing web dependencies"
	@cd $(WEB) && npm install
	@echo ""
	@echo "Done. Start the app with 'make dev-api' and 'make dev-web' in two terminals."

require-docker: ## (internal) Fail with a useful message if the Docker daemon is down
	@docker info >/dev/null 2>&1 || { \
		echo "Docker is not running. Start Docker Desktop, wait for the whale icon"; \
		echo "in the menu bar to stop animating, then try again."; \
		exit 1; \
	}

db-up: require-docker ## Start MySQL and wait until it accepts connections
	@echo "==> Starting MySQL"
	@docker compose up -d mysql
	@printf "==> Waiting for MySQL to become healthy"
	@tries=0; \
	until [ "$$(docker inspect -f '{{.State.Health.Status}}' $(DB_CONTAINER) 2>/dev/null)" = "healthy" ]; do \
		tries=$$((tries + 1)); \
		if [ $$tries -gt 60 ]; then \
			echo " timed out."; \
			echo "Check container logs with: docker compose logs mysql"; \
			exit 1; \
		fi; \
		printf "."; \
		sleep 2; \
	done; \
	echo " ready."

db-down: ## Stop MySQL (data is preserved in the mysql-data volume)
	@docker compose down

db-reset: ## Destroy the database volume and rebuild it from scratch
	@echo "This deletes all local database data. Production is untouched."
	@docker compose down -v
	@$(MAKE) db-up
	@cd $(API) && php artisan migrate

db-shell: ## Open a mysql prompt against the local pos database
	@# Password is read from the container's own environment rather than repeated here.
	@docker compose exec mysql sh -c 'mysql -uposadmin -p"$$MYSQL_PASSWORD" pos'

dev-api: ## Run the Laravel API at http://localhost:8000
	@cd $(API) && php artisan serve

dev-web: ## Run the React PWA at http://localhost:5173
	@cd $(WEB) && npm run dev

test: test-api test-web ## Run all tests

test-api: ## Run the API test suite (against the pos_test database)
	@cd $(API) && php artisan test

test-web: ## Run the web test suite
	@cd $(WEB) && npm run test

lint: ## Format the API and lint the web app
	@cd $(API) && ./vendor/bin/pint
	@cd $(WEB) && npm run lint
