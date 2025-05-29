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
