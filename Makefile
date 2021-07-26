all: help

init: ## Initialize environment
	docker-compose build
	docker-compose run --rm web bin/setup

server: ## Run server
	docker-compose run --rm --service-ports web

console: ## Run console
	docker-compose run --rm web bundle exec rails console

console-sandbox: ## Run console(sandbox)
	docker-compose run --rm web bundle exec rails console --sandbox

bundle: ## Run bundle install
	docker-compose run --rm web bundle config set clean true
	docker-compose run --rm web bundle install --jobs=4

dbinit: ## Initialize database
	docker-compose run --rm web bundle exec rails db:drop db:setup

migrate: ## Run db:migrate
	docker-compose run --rm web bundle exec rails db:migrate

minitest: ## Run test
	docker-compose run --rm -e RAILS_ENV=test web bin/rails db:test:prepare
	docker-compose run --rm -e RAILS_ENV=test web bin/rails test

rubocop: ## Run rubocop (auto correct)
	docker-compose run --rm web bundle exec rubocop --auto-correct

bash: ## Run bash in web container
	docker-compose run --rm web bash

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk -F':.*?## ' '{printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'
