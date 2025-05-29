#!/bin/bash

# Claude Worktree Installation Script for macOS

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
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}Error: This script is designed for macOS${NC}"
    exit 1
fi

# Install directory
INSTALL_DIR="$HOME/.claude-worktree"

# Create installation directory
echo -e "${GREEN}Creating installation directory...${NC}"
mkdir -p "$INSTALL_DIR"

# Check for required dependencies
echo -e "${GREEN}Checking dependencies...${NC}"

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}jq not found. Installing via Homebrew...${NC}"
    if command -v brew &> /dev/null; then
        brew install jq
    else
        echo -e "${RED}Error: Homebrew not found. Please install Homebrew first:${NC}"
        echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
fi

# Check for yq (optional but recommended)
if ! command -v yq &> /dev/null; then
    echo -e "${YELLOW}yq not found. Installing via Homebrew (recommended for YAML parsing)...${NC}"
    if command -v brew &> /dev/null; then
        brew install yq
    else
        echo -e "${YELLOW}Warning: yq not installed. YAML parsing will use fallback method.${NC}"
    fi
fi

# Check for Claude CLI
if ! command -v claude &> /dev/null; then
    echo -e "${YELLOW}Warning: 'claude' command not found in PATH${NC}"
    echo "Please ensure Claude Code is installed and accessible"
    echo "Visit: https://claude.ai/code for installation instructions"
fi

# Download the main script
echo -e "${GREEN}Installing claude-worktree script...${NC}"
cat > "$INSTALL_DIR/claude-worktree.sh" << 'SCRIPT_CONTENT'
#!/bin/bash

# Claude Worktree Manager
# This script creates a new git worktree with Claude Code integration

set -e

# Configuration
CLAUDE_WORKTREE_DIR="$HOME/.claude-worktree"
PORTS_FILE="$CLAUDE_WORKTREE_DIR/ports.json"
MIN_PORT=3000
MAX_PORT=9999

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Initialize directory structure
mkdir -p "$CLAUDE_WORKTREE_DIR"

# Initialize ports file if it doesn't exist
if [ ! -f "$PORTS_FILE" ]; then
    echo "{}" > "$PORTS_FILE"
fi

# Function to find next available port
find_available_port() {
    local start_port=${1:-$MIN_PORT}
    local port=$start_port
    
    while [ $port -le $MAX_PORT ]; do
        if ! lsof -i:$port >/dev/null 2>&1 && ! jq -e ".\"$port\"" "$PORTS_FILE" >/dev/null 2>&1; then
            echo $port
            return 0
        fi
        ((port++))
    done
    
    echo "No available ports found" >&2
    return 1
}

# Function to register port
register_port() {
    local port=$1
    local worktree_name=$2
    local worktree_path=$3
    
    jq ". + {\"$port\": {\"worktree\": \"$worktree_name\", \"path\": \"$worktree_path\", \"created\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}}" "$PORTS_FILE" > "$PORTS_FILE.tmp" && mv "$PORTS_FILE.tmp" "$PORTS_FILE"
}

# Function to unregister port
unregister_port() {
    local port=$1
    jq "del(.\"$port\")" "$PORTS_FILE" > "$PORTS_FILE.tmp" && mv "$PORTS_FILE.tmp" "$PORTS_FILE"
}

# Function to read project config
read_project_config() {
    local config_file=".claude-worktree.yml"
    if [ -f "$config_file" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Function to get config value
get_config_value() {
    local key=$1
    local default=$2
    local config_file=".claude-worktree.yml"
    
    if [ -f "$config_file" ]; then
        # Use yq if available, otherwise use a simple grep approach
        if command -v yq &> /dev/null; then
            yq eval ".$key // \"$default\"" "$config_file"
        else
            grep "^$key:" "$config_file" | sed "s/^$key: *//" || echo "$default"
        fi
    else
        echo "$default"
    fi
}

# Main function
main() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}Error: Not in a git repository${NC}"
        exit 1
    fi

    # Get the root of the git repository
    REPO_ROOT=$(git rev-parse --show-toplevel)
    cd "$REPO_ROOT"

    # Get the current branch name
    CURRENT_BRANCH=$(git branch --show-current)

    # Prompt for worktree name
    echo -e "${BLUE}Enter name for the new worktree (based on branch: $CURRENT_BRANCH):${NC}"
    read -r WORKTREE_NAME
    
    if [ -z "$WORKTREE_NAME" ]; then
        echo -e "${RED}Error: Worktree name cannot be empty${NC}"
        exit 1
    fi

    # Create worktree path
    WORKTREE_PATH="$REPO_ROOT/../$WORKTREE_NAME"

    # Check if worktree already exists
    if [ -d "$WORKTREE_PATH" ]; then
        echo -e "${RED}Error: Worktree '$WORKTREE_NAME' already exists at $WORKTREE_PATH${NC}"
        exit 1
    fi

    # Create the worktree
    echo -e "${GREEN}Creating worktree '$WORKTREE_NAME'...${NC}"
    git worktree add "$WORKTREE_PATH" "$CURRENT_BRANCH"

    # Change to the new worktree
    cd "$WORKTREE_PATH"

    # Copy dotfiles
    echo -e "${GREEN}Copying dotfiles...${NC}"
    # Copy all dot files and directories from the original repository
    find "$REPO_ROOT" -maxdepth 1 -name ".*" -not -name ".git" -not -name "." -not -name ".." | while read -r dotfile; do
        if [ -f "$dotfile" ]; then
            cp "$dotfile" "$WORKTREE_PATH/"
        elif [ -d "$dotfile" ]; then
            cp -r "$dotfile" "$WORKTREE_PATH/"
        fi
    done

    # Read project configuration
    HAS_CONFIG=$(read_project_config)

    # Run project-specific setup commands
    if [ "$HAS_CONFIG" == "true" ]; then
        echo -e "${GREEN}Running project-specific setup...${NC}"
        
        # Get setup commands from config
        SETUP_COMMANDS=$(get_config_value "setup_commands" "")
        if [ -n "$SETUP_COMMANDS" ]; then
            # Execute each setup command
            echo "$SETUP_COMMANDS" | while IFS= read -r cmd; do
                if [ -n "$cmd" ]; then
                    echo -e "${BLUE}Running: $cmd${NC}"
                    eval "$cmd"
                fi
            done
        fi
    else
        # Default Rails setup if no config
        if [ -f "Gemfile" ] && grep -q "rails" "Gemfile"; then
            echo -e "${GREEN}Detected Rails project. Running asset precompilation...${NC}"
            bundle exec rails assets:precompile
        fi
    fi

    # Find available port
    echo -e "${GREEN}Finding available port...${NC}"
    PORT=$(find_available_port)
    echo -e "${GREEN}Using port: $PORT${NC}"

    # Register the port
    register_port "$PORT" "$WORKTREE_NAME" "$WORKTREE_PATH"

    # Create session info file
    SESSION_INFO="$WORKTREE_PATH/.claude-session"
    cat > "$SESSION_INFO" << EOF
WORKTREE_NAME=$WORKTREE_NAME
PORT=$PORT
STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

    # Get server command from config
    SERVER_CMD=$(get_config_value "server_command" "foreman start -e .env.development")
    SERVER_CMD="${SERVER_CMD} -p $PORT"

    # Get Claude command from config
    CLAUDE_CMD=$(get_config_value "claude_command" "claude")

    # Create a cleanup function
    cleanup() {
        echo -e "\n${YELLOW}Cleaning up...${NC}"
        
        # Kill the server if it's running
        if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
            echo -e "${YELLOW}Stopping server (PID: $SERVER_PID)...${NC}"
            kill -TERM "$SERVER_PID" 2>/dev/null
            sleep 2
            # Force kill if still running
            kill -0 "$SERVER_PID" 2>/dev/null && kill -KILL "$SERVER_PID" 2>/dev/null
        fi
        
        # Unregister the port
        unregister_port "$PORT"
        
        # Remove session info
        rm -f "$SESSION_INFO"
        
        echo -e "${GREEN}Cleanup complete${NC}"
    }

    # Set up trap to cleanup on exit
    trap cleanup EXIT INT TERM

    # Start the server in the background
    echo -e "${GREEN}Starting server on port $PORT...${NC}"
    $SERVER_CMD &
    SERVER_PID=$!

    # Wait a bit for the server to start
    sleep 3

    # Check if server is running
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo -e "${RED}Error: Server failed to start${NC}"
        exit 1
    fi

    echo -e "${GREEN}Server started successfully (PID: $SERVER_PID)${NC}"
    echo -e "${BLUE}Server URL: http://localhost:$PORT${NC}"
    echo -e "${YELLOW}Worktree: $WORKTREE_NAME${NC}"
    echo -e "${YELLOW}Location: $WORKTREE_PATH${NC}"

    # Export environment variables for the Claude session
    export CLAUDE_WORKTREE_NAME="$WORKTREE_NAME"
    export CLAUDE_WORKTREE_PORT="$PORT"
    export CLAUDE_WORKTREE_PATH="$WORKTREE_PATH"

    # Start Claude
    echo -e "\n${GREEN}Starting Claude...${NC}"
    $CLAUDE_CMD

    # The cleanup function will be called automatically when Claude exits
}

# Run main function
main "$@"
SCRIPT_CONTENT

# Make the script executable
chmod +x "$INSTALL_DIR/claude-worktree.sh"

# Create example configuration file
echo -e "${GREEN}Creating example configuration file...${NC}"
cat > "$INSTALL_DIR/example-claude-worktree.yml" << 'CONFIG_CONTENT'
# Claude Worktree Configuration
# Place this file in your project root as .claude-worktree.yml

# Commands to run after creating the worktree and copying dotfiles
# Each command will be executed in order
setup_commands: |
  bundle install
  yarn install
  bundle exec rails db:create
  bundle exec rails db:migrate
  bundle exec rails assets:precompile

# Command to start the server
# The port will be appended automatically as -p PORT
server_command: foreman start -e .env.development

# Command to start Claude (default: claude)
claude_command: claude

# Alternative configurations for different project types:

# For a Node.js project:
# setup_commands: |
#   npm install
#   npm run build
# server_command: npm run dev
# claude_command: claude

# For a Python/Django project:
# setup_commands: |
#   python -m venv venv
#   source venv/bin/activate
#   pip install -r requirements.txt
#   python manage.py migrate
#   python manage.py collectstatic --noinput
# server_command: python manage.py runserver
# claude_command: claude

# For a simple static site:
# setup_commands: |
#   npm install
# server_command: npx http-server -p
# claude_command: claude
CONFIG_CONTENT

# Add ZSH integration
echo -e "${GREEN}Adding ZSH integration...${NC}"

# Check if .zshrc exists
if [ ! -f "$HOME/.zshrc" ]; then
    echo -e "${YELLOW}Creating ~/.zshrc...${NC}"
    touch "$HOME/.zshrc"
fi

# Check if already installed
if grep -q "Claude Worktree ZSH Integration" "$HOME/.zshrc"; then
    echo -e "${YELLOW}ZSH integration already exists in ~/.zshrc${NC}"
    echo "Skipping ZSH integration..."
else
    echo -e "${GREEN}Adding to ~/.zshrc...${NC}"
    cat >> "$HOME/.zshrc" << 'ZSH_CONTENT'

# Claude Worktree ZSH Integration
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
        jq -r 'to_entries | .[] | "Port \(.key): \(.value.worktree) (created: \(.value.created))"' "$ports_file"
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
        local git_dir=$(git rev-parse --git-dir)
        if [[ "$git_dir" =~ \.git/worktrees/(.+)$ ]]; then
            echo "${match[1]}"
        elif [ -f ".claude-session" ]; then
            grep "^WORKTREE_NAME=" ".claude-session" | cut -d'=' -f2
        fi
    fi
}

# Enhanced prompt that shows worktree name
claude_worktree_prompt() {
    local worktree=$(git_worktree_name)
    if [ -n "$worktree" ]; then
        echo "%{$fg[yellow]%}[worktree: $worktree]%{$reset_color%} "
    fi
}

# Alias for quick access
alias cw='claude-worktree'
alias cws='claude-sessions'
alias cwi='claude-worktree-info'

# Auto-cleanup function to remove stale port entries
claude-worktree-cleanup() {
    local ports_file="$CLAUDE_WORKTREE_DIR/ports.json"
    if [ -f "$ports_file" ]; then
        local temp_file=$(mktemp)
        jq 'to_entries | map(select(.value.path as $path | $path | test("^/") and (. | @sh "test -d \($path)" | @sh))) | from_entries' "$ports_file" > "$temp_file"
        mv "$temp_file" "$ports_file"
    fi
}
ZSH_CONTENT
fi

echo -e "\n${GREEN}Installation complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Claude Worktree has been installed successfully!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Reload your shell configuration:"
echo -e "   ${BLUE}source ~/.zshrc${NC}"
echo ""
echo "2. Copy the example configuration to your project:"
echo -e "   ${BLUE}cp $INSTALL_DIR/example-claude-worktree.yml /path/to/your/project/.claude-worktree.yml${NC}"
echo ""
echo "3. Navigate to your git repository and run:"
echo -e "   ${BLUE}claude-worktree${NC}"
echo "   or use the alias:"
echo -e "   ${BLUE}cw${NC}"
echo ""
echo -e "${YELLOW}Available commands:${NC}"
echo "  - claude-worktree (cw)  : Create a new Claude worktree session"
echo "  - claude-sessions (cws) : List active Claude sessions"
echo "  - claude-worktree-info (cwi) : Show current worktree info"
echo ""
echo -e "${YELLOW}To show worktree name in your prompt:${NC}"
echo "Add \$(claude_worktree_prompt) to your PROMPT variable"
echo ""
echo -e "${GREEN}Enjoy using Claude Worktree!${NC}"
