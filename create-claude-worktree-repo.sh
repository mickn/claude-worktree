#!/bin/bash

# Create Claude Worktree Repository
# This script creates all the files needed for the claude-worktree repository

set -e

echo "Creating Claude Worktree repository..."

# Create directory structure
mkdir -p claude-worktree/examples
cd claude-worktree

# Create README.md
cat > README.md << 'EOF'
# Claude Worktree Manager

A powerful workflow tool that creates isolated Git worktrees for Claude Code sessions, with automatic server management, port allocation, and project-specific configurations.

## Features

- 🌳 **Git Worktree Integration**: Creates isolated development environments without switching branches
- 🚀 **Automatic Server Management**: Starts and stops servers automatically with Claude sessions
- 🔌 **Smart Port Allocation**: Automatically finds and tracks available ports across sessions
- ⚙️ **Project-Specific Configuration**: Customize setup commands per project
- 🧹 **Automatic Cleanup**: Properly terminates servers and cleans up resources on exit
- 📊 **Session Tracking**: View all active Claude sessions and their ports
- 🎨 **ZSH Integration**: Shows worktree info in your prompt

## Quick Start

```bash
# Install
curl -sL https://raw.githubusercontent.com/yourusername/claude-worktree/main/install.sh | bash

# Reload shell
source ~/.zshrc

# Create configuration in your project
cp ~/.claude-worktree/examples/rails.claude-worktree.yml .claude-worktree.yml

# Start a Claude session
cw
```

## Installation

### Automatic Installation (Recommended)

```bash
curl -sL https://raw.githubusercontent.com/yourusername/claude-worktree/main/install.sh | bash
source ~/.zshrc
```

### Manual Installation

1. Clone this repository:
```bash
git clone https://github.com/yourusername/claude-worktree.git
cd claude-worktree
```

2. Run the install script:
```bash
./install.sh
```

3. Reload your shell:
```bash
source ~/.zshrc
```

## Configuration

Create a `.claude-worktree.yml` file in your project root:

```yaml
# Commands to run after creating the worktree
setup_commands: |
  bundle install
  yarn install
  bundle exec rails db:setup
  bundle exec rails assets:precompile

# Command to start the server (port is appended automatically)
server_command: foreman start

# Command to start Claude (default: claude)
claude_command: claude
```

See the `examples/` directory for configurations for different project types.

## Usage

### Basic Commands

```bash
# Create a new Claude worktree session
cw
# or
claude-worktree

# List all active sessions
cws
# or
claude-sessions

# Get current session info
cwi
# or
claude-worktree-info
```

### Workflow

1. Navigate to your Git repository
2. Run `cw`
3. Enter a name for your worktree when prompted
4. The tool will:
   - Create a new Git worktree
   - Copy all dotfiles from the original repository
   - Run your project-specific setup commands
   - Find an available port
   - Start your server
   - Launch Claude

### Managing Multiple Sessions

Each session runs on its own port. View all active sessions:

```bash
$ cws
Active Claude Sessions:
======================
Port 3000: feature-auth (created: 2025-05-29T10:30:00Z)
Port 3001: bugfix-api (created: 2025-05-29T11:15:00Z)
```

## Project Examples

### Rails Application

```yaml
setup_commands: |
  bundle install
  yarn install
  bundle exec rails db:setup
  bundle exec rails assets:precompile

server_command: foreman start -f Procfile.dev

claude_command: claude
```

### Node.js Application

```yaml
setup_commands: |
  npm install
  npm run build

server_command: npm run dev

claude_command: claude
```

### Python/Django Application

```yaml
setup_commands: |
  python -m venv venv
  source venv/bin/activate
  pip install -r requirements.txt
  python manage.py migrate

server_command: python manage.py runserver

claude_command: claude
```

### Docker-based Application

```yaml
setup_commands: |
  docker-compose build
  docker-compose run --rm web npm install

server_command: docker-compose up

claude_command: docker-compose exec web claude
```

## Advanced Features

### Database Cloning (Rails)

For faster setup with large databases:

```yaml
setup_commands: |
  bundle install
  DB_NAME="myapp_dev_$(date +%s)"
  createdb $DB_NAME
  pg_dump myapp_development | psql $DB_NAME
  echo "DATABASE_URL=postgresql://localhost/$DB_NAME" >> .env.local
```

### Port Organization

Organize ports by service type:
- 3000-3999: Web servers
- 4000-4999: Webpack/Asset servers
- 5000-5999: API servers
- 6000-6999: WebSocket servers

### Branch Handling

The tool automatically handles when a branch is already checked out:
1. Offers to create a new branch
2. Allows using detached HEAD
3. Provides option to cancel

### ZSH Prompt Integration

Add worktree info to your prompt:

```bash
# Basic prompt
PROMPT='$(claude_worktree_prompt)%~$ '

# With Oh My Zsh
PROMPT='$(claude_worktree_prompt)'$PROMPT

# With Powerlevel10k
typeset -g POWERLEVEL9K_CUSTOM_CLAUDE_WORKTREE='claude_worktree_prompt'
```

## Environment Variables

The following environment variables are available in your Claude session:

- `CLAUDE_WORKTREE_NAME`: Name of the current worktree
- `CLAUDE_WORKTREE_PORT`: Port number for the server
- `CLAUDE_WORKTREE_PATH`: Full path to the worktree
- `CLAUDE_WORKTREE_BRANCH`: Git branch name

## Troubleshooting

### Server fails to start

Check your `server_command` in `.claude-worktree.yml` and ensure all dependencies are installed.

### Port already in use

The tool automatically finds free ports. If issues persist:
```bash
# Clear port registry
echo "{}" > ~/.claude-worktree/ports.json

# Kill processes on Claude ports
lsof -ti:3000-9999 | xargs kill -9 2>/dev/null
```

### Branch already checked out

The tool will prompt you to:
- Create a new branch (recommended)
- Use detached HEAD
- Cancel operation

### Cleanup old worktrees

```bash
# List all worktrees
git worktree list

# Remove specific worktree
git worktree remove worktree-name

# Prune stale worktrees
git worktree prune
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Acknowledgments

- Inspired by the Claude Code workflow discussion
- Built for developers who love efficient workflows
- Special thanks to the Anthropic team for Claude

## Support

- Report issues on [GitHub Issues](https://github.com/yourusername/claude-worktree/issues)
- Check [Discussions](https://github.com/yourusername/claude-worktree/discussions) for Q&A
- Read the [Wiki](https://github.com/yourusername/claude-worktree/wiki) for detailed guides
EOF

# Create install.sh
cat > install.sh << 'EOF'
#!/bin/bash

# Claude Worktree Installation Script
# Supports both local and remote installation

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}Claude Worktree Installation Script${NC}"
echo "===================================="

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]] && [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo -e "${RED}Error: This script is designed for macOS and Linux${NC}"
    exit 1
fi

# Install directory
INSTALL_DIR="$HOME/.claude-worktree"

# Detect if we're running from a local clone or via curl
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -f "$SCRIPT_DIR/claude-worktree.sh" ]; then
    echo -e "${GREEN}Installing from local repository...${NC}"
    LOCAL_INSTALL=true
    REPO_DIR="$SCRIPT_DIR"
else
    echo -e "${GREEN}Installing from remote repository...${NC}"
    LOCAL_INSTALL=false
    REPO_URL="https://raw.githubusercontent.com/yourusername/claude-worktree/main"
fi

# Create installation directory
echo -e "${GREEN}Creating installation directory...${NC}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/examples"

# Check for required dependencies
echo -e "${GREEN}Checking dependencies...${NC}"

# Function to check and install command
check_and_install() {
    local cmd=$1
    local install_cmd=$2
    local install_name=$3
    
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${YELLOW}$cmd not found.${NC}"
        
        # Check for package managers
        if [[ "$OSTYPE" == "darwin"* ]] && command -v brew &> /dev/null; then
            echo -e "${YELLOW}Installing $install_name via Homebrew...${NC}"
            brew install $install_name
        elif command -v apt-get &> /dev/null; then
            echo -e "${YELLOW}Installing $install_name via apt...${NC}"
            sudo apt-get update && sudo apt-get install -y $install_name
        elif command -v yum &> /dev/null; then
            echo -e "${YELLOW}Installing $install_name via yum...${NC}"
            sudo yum install -y $install_name
        else
            echo -e "${RED}Error: Cannot install $install_name. Please install it manually.${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}✓ $cmd found${NC}"
    fi
}

# Check for jq
check_and_install "jq" "brew install jq" "jq"

# Check for git
check_and_install "git" "brew install git" "git"

# Check for yq (optional but recommended)
if ! command -v yq &> /dev/null; then
    echo -e "${YELLOW}yq not found (optional). You can install it later for better YAML parsing.${NC}"
else
    echo -e "${GREEN}✓ yq found${NC}"
fi

# Check for Claude CLI
if ! command -v claude &> /dev/null; then
    echo -e "${YELLOW}Warning: 'claude' command not found in PATH${NC}"
    echo "Please ensure Claude Code is installed and accessible"
    echo "Visit: https://github.com/anthropics/claude-code for installation instructions"
fi

# Install main script
echo -e "${GREEN}Installing claude-worktree script...${NC}"
if [ "$LOCAL_INSTALL" = true ]; then
    cp "$REPO_DIR/claude-worktree.sh" "$INSTALL_DIR/"
else
    # Create the main script directly
    cat > "$INSTALL_DIR/claude-worktree.sh" << 'SCRIPT_EOF'
# [Insert claude-worktree.sh content here]
SCRIPT_EOF
fi
chmod +x "$INSTALL_DIR/claude-worktree.sh"

# Install example configurations
echo -e "${GREEN}Installing example configurations...${NC}"
if [ "$LOCAL_INSTALL" = true ]; then
    if [ -d "$REPO_DIR/examples" ]; then
        cp -r "$REPO_DIR/examples/"* "$INSTALL_DIR/examples/" 2>/dev/null || true
    fi
fi

# Create a default example
cat > "$INSTALL_DIR/examples/default.claude-worktree.yml" << 'YAML_EOF'
# Claude Worktree Configuration Example
# Copy this file to your project root as .claude-worktree.yml

# Commands to run after creating the worktree
setup_commands: |
  echo "Running project setup..."
  # Add your setup commands here

# Command to start the server
# The port will be appended automatically as -p PORT
server_command: echo "No server configured"

# Command to start Claude (default: claude)
claude_command: claude
YAML_EOF

# Detect shell
if [ -n "$ZSH_VERSION" ]; then
    SHELL_RC="$HOME/.zshrc"
    SHELL_NAME="zsh"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_RC="$HOME/.bashrc"
    SHELL_NAME="bash"
else
    SHELL_RC="$HOME/.profile"
    SHELL_NAME="shell"
fi

# Add shell integration
echo -e "${GREEN}Adding $SHELL_NAME integration...${NC}"

# Check if already installed
if grep -q "Claude Worktree Integration" "$SHELL_RC" 2>/dev/null; then
    echo -e "${YELLOW}Shell integration already exists in $SHELL_RC${NC}"
    echo "Skipping shell integration..."
else
    echo -e "${GREEN}Adding to $SHELL_RC...${NC}"
    cat >> "$SHELL_RC" << 'SHELL_EOF'

# Claude Worktree Integration
export CLAUDE_WORKTREE_DIR="$HOME/.claude-worktree"
export PATH="$CLAUDE_WORKTREE_DIR:$PATH"

# Function to create a new Claude worktree session
claude-worktree() {
    if [ -f "$CLAUDE_WORKTREE_DIR/claude-worktree.sh" ]; then
        bash "$CLAUDE_WORKTREE_DIR/claude-worktree.sh" "$@"
    else
        echo "Error: claude-worktree.sh not found in $CLAUDE_WORKTREE_DIR"
        echo "Please run the installation script first."
        return 1
    fi
}

# Function to list active Claude sessions
claude-sessions() {
    local ports_file="$CLAUDE_WORKTREE_DIR/ports.json"
    if [ -f "$ports_file" ]; then
        echo "Active Claude Sessions:"
        echo "======================"
        jq -r 'to_entries | .[] | "Port \(.key): \(.value.worktree) (created: \(.value.created))"' "$ports_file" 2>/dev/null || echo "Error reading sessions"
    else
        echo "No active Claude sessions found."
    fi
}

# Function to get current worktree info
claude-worktree-info() {
    if [ -f ".claude-session" ]; then
        cat ".claude-session"
    elif [ -n "$CLAUDE_WORKTREE_NAME" ]; then
        echo "WORKTREE_NAME=$CLAUDE_WORKTREE_NAME"
        echo "PORT=$CLAUDE_WORKTREE_PORT"
        echo "PATH=$CLAUDE_WORKTREE_PATH"
    else
        echo "Not in a Claude worktree session"
    fi
}

# Function to detect if we're in a git worktree
git_worktree_name() {
    if git rev-parse --git-dir > /dev/null 2>&1; then
        local git_dir=$(git rev-parse --git-dir 2>/dev/null)
        if [[ "$git_dir" =~ \.git/worktrees/(.+)$ ]]; then
            # Extract worktree name from path
            echo "${git_dir##*/worktrees/}"
        elif [ -f ".claude-session" ]; then
            grep "^WORKTREE_NAME=" ".claude-session" 2>/dev/null | cut -d'=' -f2
        fi
    fi
}

# Enhanced prompt that shows worktree name (for zsh)
claude_worktree_prompt() {
    local worktree=$(git_worktree_name)
    if [ -n "$worktree" ]; then
        echo "[worktree: $worktree] "
    fi
}

# Alias for quick access
alias cw='claude-worktree'
alias cws='claude-sessions'
alias cwi='claude-worktree-info'

# Auto-cleanup function to remove stale port entries
claude-worktree-cleanup() {
    local ports_file="$CLAUDE_WORKTREE_DIR/ports.json"
    if [ -f "$ports_file" ] && command -v jq &> /dev/null; then
        local temp_file=$(mktemp)
        jq '.' "$ports_file" > "$temp_file" 2>/dev/null && mv "$temp_file" "$ports_file" || rm -f "$temp_file"
    fi
}
SHELL_EOF
fi

# Create uninstall script
echo -e "${GREEN}Creating uninstall script...${NC}"
cat > "$INSTALL_DIR/uninstall.sh" << 'UNINSTALL_EOF'
#!/bin/bash

# Claude Worktree Uninstall Script

echo "Uninstalling Claude Worktree..."

# Remove installation directory
rm -rf "$HOME/.claude-worktree"

# Remove shell integration
for rc in ~/.zshrc ~/.bashrc ~/.profile; do
    if [ -f "$rc" ]; then
        # Create backup
        cp "$rc" "$rc.claude-worktree-backup"
        # Remove Claude Worktree section
        sed -i.bak '/# Claude Worktree Integration/,/^$/d' "$rc"
        echo "Removed integration from $rc (backup: $rc.claude-worktree-backup)"
    fi
done

echo "Claude Worktree has been uninstalled."
echo "Your git worktrees remain intact."
UNINSTALL_EOF
chmod +x "$INSTALL_DIR/uninstall.sh"

# Final instructions
echo -e "\n${GREEN}Installation complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Claude Worktree has been installed successfully!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Reload your shell configuration:"
echo -e "   ${BLUE}source $SHELL_RC${NC}"
echo ""
echo "2. Copy an example configuration to your project:"
echo -e "   ${BLUE}cp $INSTALL_DIR/examples/default.claude-worktree.yml /path/to/your/project/.claude-worktree.yml${NC}"
echo ""
echo "3. Navigate to your git repository and run:"
echo -e "   ${BLUE}claude-worktree${NC}"
echo "   or use the alias:"
echo -e "   ${BLUE}cw${NC}"
echo ""
echo -e "${YELLOW}Available commands:${NC}"
echo "  - claude-worktree (cw)      : Create a new Claude worktree session"
echo "  - claude-sessions (cws)     : List active Claude sessions"
echo "  - claude-worktree-info (cwi): Show current worktree info"
echo ""
echo -e "${YELLOW}Example configurations available in:${NC}"
echo "  $INSTALL_DIR/examples/"
echo ""
echo -e "${YELLOW}To uninstall:${NC}"
echo "  $INSTALL_DIR/uninstall.sh"
echo ""
echo -e "${GREEN}Enjoy using Claude Worktree!${NC}"

# Reminder for Claude CLI
if ! command -v claude &> /dev/null; then
    echo ""
    echo -e "${RED}Important: Claude CLI not found!${NC}"
    echo "Please install Claude Code from:"
    echo "https://github.com/anthropics/claude-code"
fi
EOF

# NOTE: The install.sh above has a placeholder for claude-worktree.sh content
# In the real file, you'd insert the full claude-worktree.sh content where indicated

# Create the main claude-worktree.sh script
# Copy the full content from the claude-worktree-main-script artifact here

# Create .gitignore
cat > .gitignore << 'EOF'
# OS files
.DS_Store
Thumbs.db

# Editor files
*.swp
*.swo
*~
.vscode/
.idea/

# Temporary files
*.tmp
*.bak
*.log

# Installation artifacts
ports.json

# Test worktrees
test-*
worktree-*

# Local configuration
.claude-worktree.yml.local
EOF

# Create LICENSE
cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2024 Claude Worktree Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

# Create CONTRIBUTING.md
cat > CONTRIBUTING.md << 'EOF'
# Contributing to Claude Worktree

We love your input! We want to make contributing to Claude Worktree as easy and transparent as possible.

## Development Process

1. Fork the repo and create your branch from `main`
2. If you've added code that should be tested, add tests
3. If you've changed APIs, update the documentation
4. Ensure the test suite passes
5. Make sure your code lints
6. Issue that pull request!

## Any contributions you make will be under the MIT Software License

When you submit code changes, your submissions are understood to be under the same [MIT License](LICENSE) that covers the project.

## Report bugs using Github's [issues](https://github.com/yourusername/claude-worktree/issues)

We use GitHub issues to track public bugs. Report a bug by [opening a new issue](https://github.com/yourusername/claude-worktree/issues/new).

## Write bug reports with detail, background, and sample code

**Great Bug Reports** tend to have:

- A quick summary and/or background
- Steps to reproduce
  - Be specific!
  - Give sample code if you can
- What you expected would happen
- What actually happens
- Notes (possibly including why you think this might be happening, or stuff you tried that didn't work)

## License

By contributing, you agree that your contributions will be licensed under its MIT License.
EOF

# Create test.sh
cat > test.sh << 'EOF'
#!/bin/bash

# Claude Worktree Test Script
# This script tests the installation and basic functionality

set -e

echo "Testing Claude Worktree..."

# Test 1: Check if installed
if [ ! -f "$HOME/.claude-worktree/claude-worktree.sh" ]; then
    echo "❌ Test failed: Claude Worktree not installed"
    exit 1
fi
echo "✅ Installation check passed"

# Test 2: Check if commands are available
if ! command -v claude-worktree &> /dev/null; then
    echo "❌ Test failed: claude-worktree command not available"
    echo "   Please run: source ~/.zshrc"
    exit 1
fi
echo "✅ Command availability check passed"

# Test 3: Check dependencies
for cmd in git jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ Test failed: $cmd not installed"
        exit 1
    fi
done
echo "✅ Dependencies check passed"

# Test 4: Test help command
claude-worktree --help > /dev/null 2>&1 || {
    echo "❌ Test failed: Help command failed"
    exit 1
}
echo "✅ Help command check passed"

# Test 5: Check ports file
if [ ! -f "$HOME/.claude-worktree/ports.json" ]; then
    echo "⚠️  Warning: ports.json not found (will be created on first use)"
fi

echo ""
echo "🎉 All tests passed!"
echo ""
echo "Next steps:"
echo "1. Navigate to a git repository"
echo "2. Create a .claude-worktree.yml configuration file"
echo "3. Run 'cw' to start a Claude worktree session"
EOF

# Create Makefile
cat > Makefile << 'EOF'
.PHONY: install uninstall test examples clean help

help:
	@echo "Claude Worktree Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make install    - Install Claude Worktree"
	@echo "  make uninstall  - Uninstall Claude Worktree"
	@echo "  make test       - Run tests"
	@echo "  make examples   - Create example configuration files"
	@echo "  make clean      - Clean temporary files"
	@echo "  make help       - Show this help message"

install:
	@echo "Installing Claude Worktree..."
	@./install.sh

uninstall:
	@echo "Uninstalling Claude Worktree..."
	@~/.claude-worktree/uninstall.sh

test:
	@./test.sh

examples:
	@cd examples && ./create-all.sh

clean:
	@echo "Cleaning temporary files..."
	@rm -f *.tmp *.bak
	@rm -rf test-worktree-*

.DEFAULT_GOAL := help
EOF

# Create example configurations script
cat > examples/create-all.sh << 'EOF'
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
EOF

# Make all scripts executable
chmod +x install.sh test.sh examples/create-all.sh

# Create examples
cd examples && ./create-all.sh && cd ..

# Initialize git repository
git init
git add .
git commit -m "Initial commit of Claude Worktree Manager"

echo ""
echo "✅ Claude Worktree repository created successfully!"
echo ""
echo "📁 Repository structure:"
tree -L 2 2>/dev/null || ls -la
echo ""
echo "📝 Next steps:"
echo "1. Update the repository URLs in README.md and install.sh"
echo "2. Add the claude-worktree.sh content to install.sh (where indicated)"
echo "3. Create a GitHub repository"
echo "4. Push to GitHub:"
echo "   git remote add origin https://github.com/YOUR_USERNAME/claude-worktree.git"
echo "   git branch -M main"
echo "   git push -u origin main"
echo ""
echo "5. Test the installation:"
echo "   ./install.sh"
echo "   source ~/.zshrc"
echo "   ./test.sh"