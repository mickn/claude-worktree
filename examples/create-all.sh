#!/bin/bash

# This script creates all example configuration files

echo "Creating example configuration files..."

# Rails
cat > rails.claude-worktree.yml << 'YAML'
# Configuration for Ruby on Rails projects
setup_commands: |
  bundle install
  yarn install
  bundle exec rails db:create db:migrate db:seed
  bundle exec rails assets:precompile
  bundle exec rails tmp:clear

server_command: foreman start -f Procfile.dev
claude_command: claude
YAML

# Node.js
cat > node.claude-worktree.yml << 'YAML'
# Configuration for Node.js projects
setup_commands: |
  npm install
  npm run build
  cp .env.example .env || true

server_command: npm run dev
claude_command: claude
YAML

# Python
cat > python.claude-worktree.yml << 'YAML'
# Configuration for Python/Django projects
setup_commands: |
  python -m venv venv
  source venv/bin/activate
  pip install -r requirements.txt
  python manage.py migrate
  python manage.py collectstatic --noinput

server_command: source venv/bin/activate && python manage.py runserver
claude_command: source venv/bin/activate && claude
YAML

# Docker
cat > docker.claude-worktree.yml << 'YAML'
# Configuration for Docker-based projects
setup_commands: |
  docker-compose build
  docker-compose run --rm web bundle install
  docker-compose run --rm web yarn install
  docker-compose run --rm web rails db:create db:migrate db:seed

server_command: docker-compose up
claude_command: docker-compose exec web claude
YAML

# Next.js
cat > nextjs.claude-worktree.yml << 'YAML'
# Configuration for Next.js projects
setup_commands: |
  npm install
  npm run build
  cp .env.local.example .env.local || true
  npx prisma generate || true
  npx prisma migrate deploy || true

server_command: npm run dev
claude_command: claude
YAML

# Laravel
cat > laravel.claude-worktree.yml << 'YAML'
# Configuration for Laravel projects
setup_commands: |
  composer install
  npm install
  cp .env.example .env
  php artisan key:generate
  php artisan migrate --seed
  npm run build

server_command: php artisan serve
claude_command: claude
YAML

# Go
cat > golang.claude-worktree.yml << 'YAML'
# Configuration for Go projects
setup_commands: |
  go mod download
  go build -o app .
  cp .env.example .env || true

server_command: go run .
claude_command: claude
YAML

# Java Spring
cat > java-spring.claude-worktree.yml << 'YAML'
# Configuration for Java Spring Boot projects
setup_commands: |
  ./mvnw clean install
  cp src/main/resources/application.yml.example src/main/resources/application.yml || true

server_command: ./mvnw spring-boot:run
claude_command: claude
YAML

# Rust
cat > rust.claude-worktree.yml << 'YAML'
# Configuration for Rust projects
setup_commands: |
  cargo build
  cargo test
  cp .env.example .env || true

server_command: cargo run
claude_command: claude
YAML

# Minimal
cat > minimal.claude-worktree.yml << 'YAML'
# Minimal configuration
setup_commands: |
  echo "Setting up worktree..."

server_command: echo "No server needed"
claude_command: claude
YAML

echo "✅ Created all example configuration files!"
