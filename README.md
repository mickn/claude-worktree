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
curl -sL https://raw.githubusercontent.com/mickn/claude-worktree/main/install.sh | bash

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
curl -sL https://raw.githubusercontent.com/mickn/claude-worktree/main/install.sh | bash
source ~/.zshrc
```

### Manual Installation

1. Clone this repository:
```bash
git clone https://github.com/mickn/claude-worktree.git
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

- Report issues on [GitHub Issues](https://github.com/mickn/claude-worktree/issues)
- Check [Discussions](https://github.com/mickn/claude-worktree/discussions) for Q&A
- Read the [Wiki](https://github.com/mickn/claude-worktree/wiki) for detailed guides
