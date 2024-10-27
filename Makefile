# Variables
DOCKER_REGISTRY=langgenius
WEB_IMAGE=$(DOCKER_REGISTRY)/dify-web
API_IMAGE=$(DOCKER_REGISTRY)/dify-api
VERSION=latest

PYTHON_VERSION := 3.10
POETRY := poetry
DOCKER_COMPOSE := docker compose
NODE_VERSION := 18

# Phony targets
.PHONY: build-web build-api push-web push-api build-all push-all build-push-all

# デフォルトターゲット
all: setup

# 初期セットアップ
setup: install-deps setup-env start-middleware install-backend install-frontend migrate

# 依存関係のインストール
install-deps:
	@echo "必要なツールをインストール中..."
	@command -v poetry >/dev/null 2>&1 || curl -sSL https://install.python-poetry.org | python3 -
	@command -v nvm >/dev/null 2>&1 || curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
	@. ~/.nvm/nvm.sh && nvm install $(NODE_VERSION)

# 環境設定
setup-env:
	@echo "環境ファイルを設定中..."
	@cd api && cp .env.example .env
	@cd web && cp .env.example .env.local
	@cd docker && cp middleware.env.example middleware.env
	@cd api && secret_key=$$(openssl rand -base64 42) && sed -i.bak "s|^SECRET_KEY=.*|SECRET_KEY=$$secret_key|" .env

# ミドルウェアの起動
start-middleware:
	@echo "ミドルウェアを起動中..."
	@cd docker && $(DOCKER_COMPOSE) -f docker-compose.middleware.yaml --profile weaviate -p dify up -d

# バックエンドのインストール
install-backend:
	@echo "バックエンドの依存関係をインストール中..."
	@cd api && $(POETRY) env use $(PYTHON_VERSION)
	@cd api && $(POETRY) install

# フロントエンドのインストール
install-frontend:
	@echo "フロントエンドの依存関係をインストール中..."
	@cd web && npm install

# データベースマイグレーション
migrate:
	@echo "データベースをマイグレート中..."
	@cd api && $(POETRY) run python -m flask db upgrade

# Docker build targets
build-web:
	@echo "Building web Docker image: $(WEB_IMAGE):$(VERSION)..."
	docker build -t $(WEB_IMAGE):$(VERSION) ./web
	@echo "Web Docker image built successfully: $(WEB_IMAGE):$(VERSION)"

build-api:
	@echo "Building API Docker image: $(API_IMAGE):$(VERSION)..."
	docker build -t $(API_IMAGE):$(VERSION) ./api
	@echo "API Docker image built successfully: $(API_IMAGE):$(VERSION)"

# Push Docker images
push-web:
	@echo "Pushing web Docker image: $(WEB_IMAGE):$(VERSION)..."
	docker push $(WEB_IMAGE):$(VERSION)
	@echo "Web Docker image pushed successfully: $(WEB_IMAGE):$(VERSION)"

push-api:
	@echo "Pushing API Docker image: $(API_IMAGE):$(VERSION)..."
	docker push $(API_IMAGE):$(VERSION)
	@echo "API Docker image pushed successfully: $(API_IMAGE):$(VERSION)"

# Build all images
build-all: build-web build-api

# Push all images
push-all: push-web push-api

build-push-api: build-api push-api
build-push-web: build-web push-web

# Build and push all images
build-push-all: build-all push-all
	@echo "All Docker images have been built and pushed."

# Development server targets
start:
	@echo "開発サーバーを起動中..."
	@make start-backend & make start-frontend & make start-worker

start-backend:
	@echo "バックエンドを起動中..."
	@cd api && $(POETRY) run python -m flask run --host 0.0.0.0 --port=5001 --debug

start-frontend:
	@echo "フロントエンドを起動中..."
	@cd web && npm run dev

start-worker:
	@echo "ワーカーを起動中..."
	@cd api && $(POETRY) run python -m celery -A app.celery worker -P gevent -c 1 --loglevel INFO -Q dataset,generation,mail,ops_trace,app_deletion

# サービスの停止
stop:
	@echo "サービスを停止中..."
	@cd docker && $(DOCKER_COMPOSE) -f docker-compose.middleware.yaml -p dify down
	@pkill -f "flask run"
	@pkill -f "npm run dev"
	@pkill -f "celery"

# テストの実行
test:
	@echo "テストを実行中..."
	@cd api && $(POETRY) run bash dev/pytest/pytest_all_tests.sh

# クリーンアップ
clean:
	@echo "クリーンアップ中..."
	@make stop
	@cd api && rm -rf .env __pycache__ .pytest_cache
	@cd web && rm -rf .env.local node_modules .next