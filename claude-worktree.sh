#!/bin/bash

# Claude Worktree Manager
# Creates isolated git worktrees for Claude Code sessions with automatic server management

set -e

# Configuration
CLAUDE_WORKTREE_DIR="$HOME/.claude-worktree"
PORTS_FILE="$CLAUDE_WORKTREE_DIR/ports.json"
SESSIONS_FILE="$CLAUDE_WORKTREE_DIR/sessions.json"
MIN_PORT=3000
MAX_PORT=9999

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Initialize directory structure
mkdir -p "$CLAUDE_WORKTREE_DIR"

# Initialize ports file if it doesn't exist
if [ ! -f "$PORTS_FILE" ]; then
    echo "{}" > "$PORTS_FILE"
fi

# Initialize sessions file if it doesn't exist
if [ ! -f "$SESSIONS_FILE" ]; then
    echo "{}" > "$SESSIONS_FILE"
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

    local temp_file=$(mktemp)
    jq ". + {\"$port\": {\"worktree\": \"$worktree_name\", \"path\": \"$worktree_path\", \"created\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}}" "$PORTS_FILE" > "$temp_file" && mv "$temp_file" "$PORTS_FILE"
}

# Function to unregister port
unregister_port() {
    local port=$1
    local temp_file=$(mktemp)
    jq "del(.\"$port\")" "$PORTS_FILE" > "$temp_file" && mv "$temp_file" "$PORTS_FILE"
}

# Function to get config value
get_config_value() {
    local key=$1
    local default=$2
    local config_file=".claude-worktree.yml"

    if [ -f "$config_file" ]; then
        if command -v yq &> /dev/null; then
            yq eval ".$key // \"$default\"" "$config_file" 2>/dev/null || echo "$default"
        else
            grep "^$key:" "$config_file" 2>/dev/null | sed "s/^$key: *//" || echo "$default"
        fi
    else
        echo "$default"
    fi
}

# Function to get multiline config
get_multiline_config() {
    local key=$1
    local config_file=".claude-worktree.yml"

    if [ -f "$config_file" ]; then
        if command -v yq &> /dev/null; then
            yq eval ".$key" "$config_file" 2>/dev/null | grep -v "^null$"
        else
            awk "/^$key:/ {flag=1; next} /^[^ ]/ {flag=0} flag" "$config_file" 2>/dev/null
        fi
    fi
}

# Function to create isolated database
create_database() {
    local db_type=$1
    local original_db=$2
    local worktree_name=$3
    local db_name="${original_db}_${worktree_name//-/_}"
    
    echo -e "${BLUE}Creating isolated database: $db_name${NC}" >&2
    
    case $db_type in
        "postgresql"|"postgres")
            # Check if database already exists
            if psql -lqt | cut -d \| -f 1 | grep -qw "$db_name"; then
                echo -e "${YELLOW}Database $db_name already exists${NC}" >&2
            else
                # Create database
                createdb "$db_name" 2>/dev/null || {
                    echo -e "${YELLOW}Failed to create database. Trying with psql...${NC}" >&2
                    psql -c "CREATE DATABASE \"$db_name\";" 2>/dev/null || {
                        echo -e "${RED}Error: Failed to create PostgreSQL database${NC}" >&2
                        return 1
                    }
                }
                
                # Clone data if original database exists
                if psql -lqt | cut -d \| -f 1 | grep -qw "$original_db"; then
                    echo -e "${BLUE}Cloning data from $original_db...${NC}" >&2
                    pg_dump "$original_db" | psql "$db_name" >/dev/null 2>&1 || {
                        echo -e "${YELLOW}Warning: Failed to clone data, starting with empty database${NC}" >&2
                    }
                fi
            fi
            ;;
        
        "mysql")
            # Check if database already exists
            if mysql -e "SHOW DATABASES;" 2>/dev/null | grep -qw "$db_name"; then
                echo -e "${YELLOW}Database $db_name already exists${NC}" >&2
            else
                # Create database
                mysql -e "CREATE DATABASE \`$db_name\`;" 2>/dev/null || {
                    echo -e "${RED}Error: Failed to create MySQL database${NC}" >&2
                    return 1
                }
                
                # Clone data if original database exists
                if mysql -e "SHOW DATABASES;" 2>/dev/null | grep -qw "$original_db"; then
                    echo -e "${BLUE}Cloning data from $original_db...${NC}" >&2
                    mysqldump "$original_db" 2>/dev/null | mysql "$db_name" 2>/dev/null || {
                        echo -e "${YELLOW}Warning: Failed to clone data, starting with empty database${NC}" >&2
                    }
                fi
            fi
            ;;
        
        *)
            echo -e "${YELLOW}Unknown database type: $db_type${NC}" >&2
            return 1
            ;;
    esac
    
    echo "$db_name"
}

# Function to update database configuration
update_database_config() {
    local framework=$1
    local db_name=$2
    local worktree_path=$3
    
    case $framework in
        "rails")
            # Update Rails database.yml
            if [ -f "$worktree_path/config/database.yml" ]; then
                echo -e "${BLUE}Updating Rails database configuration...${NC}"
                # Create a backup
                cp "$worktree_path/config/database.yml" "$worktree_path/config/database.yml.backup"
                
                # Update database name for development and test environments
                if command -v yq &> /dev/null; then
                    yq eval ".development.database = \"$db_name\"" -i "$worktree_path/config/database.yml"
                    yq eval ".test.database = \"${db_name}_test\"" -i "$worktree_path/config/database.yml"
                else
                    # Fallback to sed
                    sed -i.bak "s/database: .*_development/database: $db_name/" "$worktree_path/config/database.yml"
                    sed -i.bak "s/database: .*_test/database: ${db_name}_test/" "$worktree_path/config/database.yml"
                fi
            fi
            ;;
        
        "django")
            # Update Django settings
            local settings_file="$worktree_path/settings.py"
            [ -f "$worktree_path/config/settings.py" ] && settings_file="$worktree_path/config/settings.py"
            [ -f "$worktree_path/project/settings.py" ] && settings_file="$worktree_path/project/settings.py"
            
            if [ -f "$settings_file" ]; then
                echo -e "${BLUE}Updating Django database configuration...${NC}"
                # This is a simplified approach - in practice, you might want to use environment variables
                echo "# Claude Worktree Database Override" >> "$settings_file"
                echo "import os" >> "$settings_file"
                echo "if os.environ.get('CLAUDE_WORKTREE_DB'):" >> "$settings_file"
                echo "    DATABASES['default']['NAME'] = os.environ['CLAUDE_WORKTREE_DB']" >> "$settings_file"
            fi
            ;;
        
        "laravel")
            # Update Laravel .env file
            if [ -f "$worktree_path/.env" ]; then
                echo -e "${BLUE}Updating Laravel database configuration...${NC}"
                sed -i.bak "s/^DB_DATABASE=.*/DB_DATABASE=$db_name/" "$worktree_path/.env"
            fi
            ;;
    esac
}

# Function to drop database
drop_database() {
    local db_type=$1
    local db_name=$2
    
    echo -e "${YELLOW}Dropping database: $db_name${NC}"
    
    case $db_type in
        "postgresql"|"postgres")
            dropdb "$db_name" 2>/dev/null || {
                psql -c "DROP DATABASE IF EXISTS \"$db_name\";" 2>/dev/null || {
                    echo -e "${YELLOW}Warning: Failed to drop PostgreSQL database${NC}"
                }
            }
            ;;
        
        "mysql")
            mysql -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null || {
                echo -e "${YELLOW}Warning: Failed to drop MySQL database${NC}"
            }
            ;;
    esac
}

# Function to register session with database info
register_session() {
    local worktree_name=$1
    local worktree_path=$2
    local port=$3
    local db_info=$4
    
    local temp_file=$(mktemp)
    jq ". + {\"$worktree_name\": {
        \"path\": \"$worktree_path\",
        \"port\": $port,
        \"database\": $db_info,
        \"created\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
    }}" "$SESSIONS_FILE" > "$temp_file" && mv "$temp_file" "$SESSIONS_FILE"
}

# Function to get session info
get_session_info() {
    local worktree_name=$1
    jq -r ".\"$worktree_name\"" "$SESSIONS_FILE" 2>/dev/null
}

# Function to unregister session
unregister_session() {
    local worktree_name=$1
    local temp_file=$(mktemp)
    jq "del(.\"$worktree_name\")" "$SESSIONS_FILE" > "$temp_file" && mv "$temp_file" "$SESSIONS_FILE"
}

# Function to handle branch checkout issues
handle_branch_checkout() {
    local branch=$1
    local worktree_name=$2

    # Check if branch is already checked out
    local current_worktree=$(pwd)
    local existing_worktree=""

    # Check all worktrees for this branch
    while IFS= read -r line; do
        if [[ "$line" =~ ^worktree ]]; then
            worktree_path=$(echo "$line" | cut -d' ' -f2)
        elif [[ "$line" =~ ^branch\ refs/heads/$branch$ ]]; then
            if [ "$worktree_path" != "$current_worktree" ]; then
                existing_worktree="$worktree_path"
                break
            fi
        fi
    done < <(git worktree list --porcelain)

    if [ -n "$existing_worktree" ]; then
        echo -e "${YELLOW}Branch '$branch' is already checked out at: $existing_worktree${NC}"
        echo -e "${BLUE}Choose an option:${NC}"
        echo "1) Create a new branch '$branch-$worktree_name'"
        echo "2) Use detached HEAD (no branch)"
        echo "3) Select a different branch"
        echo "4) Cancel"

        read -r -p "Enter choice (1-4): " choice

        case $choice in
            1)
                local new_branch="$branch-$worktree_name"
                echo -e "${GREEN}Creating new branch '$new_branch'...${NC}"
                git branch "$new_branch" "$branch" 2>/dev/null || {
                    new_branch="$branch-$worktree_name-$(date +%s)"
                    git branch "$new_branch" "$branch"
                }
                echo "$new_branch"
                ;;
            2)
                echo "HEAD"
                ;;
            3)
                echo -e "${BLUE}Available branches:${NC}"
                git branch -a | grep -v "HEAD detached" | sed 's/^[* ]*//' | sort -u
                read -r -p "Enter branch name: " selected_branch
                echo "$selected_branch"
                ;;
            *)
                echo -e "${RED}Cancelled${NC}"
                exit 1
                ;;
        esac
    else
        echo "$branch"
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

    # Get repository name
    REPO_NAME=$(basename "$REPO_ROOT")

    # Get the current branch name
    BRANCH_NAME=$(git branch --show-current || echo "HEAD")

    # Show header
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${CYAN}    Claude Worktree Manager${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${BLUE}Repository:${NC} $REPO_NAME"
    echo -e "${BLUE}Branch:${NC} $BRANCH_NAME"
    echo -e "${CYAN}───────────────────────────────────────────${NC}"

    # Prompt for worktree name
    echo -e "${BLUE}Enter name for the new worktree:${NC}"
    read -r WORKTREE_NAME

    if [ -z "$WORKTREE_NAME" ]; then
        echo -e "${RED}Error: Worktree name cannot be empty${NC}"
        exit 1
    fi

    # Sanitize worktree name
    WORKTREE_NAME=$(echo "$WORKTREE_NAME" | tr ' ' '-' | tr -cd '[:alnum:]-_')

    # Create worktree path (use absolute path)
    WORKTREE_PATH=$(cd "$REPO_ROOT/.." && pwd)/"$WORKTREE_NAME"

    # Check if worktree already exists
    if [ -d "$WORKTREE_PATH" ]; then
        echo -e "${YELLOW}Worktree '$WORKTREE_NAME' already exists at $WORKTREE_PATH${NC}"
        
        # Check if it's a valid git worktree from the main repository
        if (cd "$REPO_ROOT" && git worktree list | grep -q "$WORKTREE_PATH"); then
            echo -e "${BLUE}Would you like to reuse this existing worktree? (y/n)${NC}"
            read -r response
            
            if [[ "$response" =~ ^[Yy]$ ]]; then
                echo -e "${GREEN}Reusing existing worktree...${NC}"
                cd "$WORKTREE_PATH"
                
                # Get the branch name from the worktree
                BRANCH_TO_USE=$(git branch --show-current || echo "HEAD")
                
                # Skip worktree creation, jump to setup
                REUSE_WORKTREE=true
            else
                echo -e "${RED}Cancelled${NC}"
                exit 1
            fi
        else
            echo -e "${RED}Error: Directory exists but is not a valid git worktree${NC}"
            echo -e "${YELLOW}Please remove or rename it and try again${NC}"
            exit 1
        fi
    else
        REUSE_WORKTREE=false
    fi

    # Only handle branch and create worktree if not reusing
    if [ "$REUSE_WORKTREE" = false ]; then
        # Handle branch checkout issues - automatically create a new branch with worktree name
        echo -e "${YELLOW}Checking branch availability...${NC}"
        
        # Check if the current branch is already checked out elsewhere
        if git worktree list --porcelain | grep -q "branch refs/heads/$BRANCH_NAME"; then
            # Create a new branch with the worktree name
            echo -e "${GREEN}Branch '$BRANCH_NAME' is already checked out. Creating new branch '$WORKTREE_NAME'...${NC}"
            git branch "$WORKTREE_NAME" "$BRANCH_NAME" 2>/dev/null || {
                # If branch already exists, create with timestamp
                WORKTREE_BRANCH="$WORKTREE_NAME-$(date +%s)"
                echo -e "${YELLOW}Branch '$WORKTREE_NAME' already exists. Creating '$WORKTREE_BRANCH' instead...${NC}"
                git branch "$WORKTREE_BRANCH" "$BRANCH_NAME"
                WORKTREE_NAME="$WORKTREE_BRANCH"
            }
            BRANCH_TO_USE="$WORKTREE_NAME"
        else
            # Use the current branch as-is
            BRANCH_TO_USE="$BRANCH_NAME"
        fi

        # NOW create the worktree with the correct branch
        echo -e "${GREEN}Creating worktree '$WORKTREE_NAME' with branch '$BRANCH_TO_USE'...${NC}"
        git worktree add "$WORKTREE_PATH" "$BRANCH_TO_USE"

        # Change to the new worktree
        cd "$WORKTREE_PATH"
    fi

    # Only copy dotfiles for new worktrees
    if [ "$REUSE_WORKTREE" = false ]; then
        echo -e "${GREEN}Copying dotfiles...${NC}"
        find "$REPO_ROOT" -maxdepth 1 -name ".*" -not -name ".git" -not -name "." -not -name ".." | while read -r dotfile; do
            if [ -e "$dotfile" ]; then
                cp -r "$dotfile" "$WORKTREE_PATH/" 2>/dev/null || true
            fi
        done
    fi
    
    # Set up isolated database if configured
    DB_CONFIG=$(get_config_value "database" "")
    DB_TYPE=""
    DB_NAME=""
    DB_CREATED=false
    
    if [ -n "$DB_CONFIG" ] || [ -f "config/database.yml" ] || [ -f ".env" ] || [ -f "settings.py" ]; then
        # Detect database type and name
        if [ -f ".claude-worktree.yml" ] && command -v yq &> /dev/null; then
            DB_TYPE=$(yq eval ".database.type" ".claude-worktree.yml" 2>/dev/null | grep -v "^null$" || echo "")
            DB_NAME=$(yq eval ".database.name" ".claude-worktree.yml" 2>/dev/null | grep -v "^null$" || echo "")
        fi
        
        # Auto-detect if not specified
        if [ -z "$DB_TYPE" ]; then
            if [ -f "config/database.yml" ]; then
                # Rails project
                if grep -q "adapter:.*postgresql" "config/database.yml" 2>/dev/null; then
                    DB_TYPE="postgresql"
                elif grep -q "adapter:.*mysql" "config/database.yml" 2>/dev/null; then
                    DB_TYPE="mysql"
                fi
                
                # Get database name if not specified
                if [ -z "$DB_NAME" ] && command -v yq &> /dev/null; then
                    DB_NAME=$(yq eval ".development.database" "config/database.yml" 2>/dev/null | grep -v "^null$" || echo "")
                fi
            elif [ -f ".env" ] && grep -q "DB_CONNECTION" ".env"; then
                # Laravel project
                DB_TYPE=$(grep "^DB_CONNECTION=" ".env" | cut -d'=' -f2)
                DB_NAME=$(grep "^DB_DATABASE=" ".env" | cut -d'=' -f2)
            fi
        fi
        
        # Create isolated database if we have the info
        if [ -n "$DB_TYPE" ] && [ -n "$DB_NAME" ]; then
            # Check if database server is running
            if [ "$DB_TYPE" = "postgresql" ] || [ "$DB_TYPE" = "postgres" ]; then
                # Check multiple ways to see if PostgreSQL is available
                if ! pg_isready >/dev/null 2>&1 && ! psql -c "SELECT 1" >/dev/null 2>&1; then
                    echo -e "${YELLOW}Warning: PostgreSQL server is not accessible. Skipping database isolation.${NC}"
                    echo -e "${YELLOW}Start PostgreSQL (or Postgres.app) and re-run to create isolated database.${NC}"
                    NEW_DB_NAME=""
                else
                    NEW_DB_NAME=$(create_database "$DB_TYPE" "$DB_NAME" "$WORKTREE_NAME") || {
                        echo -e "${YELLOW}Warning: Failed to create isolated database${NC}"
                        NEW_DB_NAME=""
                    }
                fi
            elif [ "$DB_TYPE" = "mysql" ]; then
                if ! mysqladmin ping >/dev/null 2>&1; then
                    echo -e "${YELLOW}Warning: MySQL server is not running. Skipping database isolation.${NC}"
                    echo -e "${YELLOW}Start MySQL and re-run to create isolated database.${NC}"
                    NEW_DB_NAME=""
                else
                    NEW_DB_NAME=$(create_database "$DB_TYPE" "$DB_NAME" "$WORKTREE_NAME") || {
                        echo -e "${YELLOW}Warning: Failed to create isolated database${NC}"
                        NEW_DB_NAME=""
                    }
                fi
            else
                NEW_DB_NAME=$(create_database "$DB_TYPE" "$DB_NAME" "$WORKTREE_NAME") || {
                    echo -e "${YELLOW}Warning: Failed to create isolated database${NC}"
                    NEW_DB_NAME=""
                }
            fi
            
            if [ -n "$NEW_DB_NAME" ]; then
                DB_CREATED=true
                # Detect framework and update config
                if [ -f "config/database.yml" ] && [ -f "Gemfile" ]; then
                    update_database_config "rails" "$NEW_DB_NAME" "$WORKTREE_PATH"
                elif [ -f ".env" ] && [ -f "artisan" ]; then
                    update_database_config "laravel" "$NEW_DB_NAME" "$WORKTREE_PATH"
                elif [ -f "manage.py" ] || [ -f "settings.py" ]; then
                    update_database_config "django" "$NEW_DB_NAME" "$WORKTREE_PATH"
                    export CLAUDE_WORKTREE_DB="$NEW_DB_NAME"
                fi
            fi
        fi
    fi

    # Run setup commands - always for reused worktrees, optionally for new ones
    if [ "$REUSE_WORKTREE" = true ]; then
        echo -e "${BLUE}Re-running setup commands for existing worktree...${NC}"
    fi
    
    # Check for configuration
    if [ -f ".claude-worktree.yml" ]; then
        echo -e "${GREEN}Found configuration file${NC}"
        echo -e "${GREEN}Running project-specific setup...${NC}"

        # Get setup commands from config
        SETUP_COMMANDS=$(get_multiline_config "setup_commands")
        if [ -n "$SETUP_COMMANDS" ]; then
            echo "$SETUP_COMMANDS" | while IFS= read -r cmd; do
                if [ -n "$cmd" ] && [ "$cmd" != "|" ]; then
                    echo -e "${BLUE}Running: $cmd${NC}"
                    eval "$cmd" || {
                        echo -e "${YELLOW}Warning: Command failed: $cmd${NC}"
                        echo -e "${YELLOW}Continuing...${NC}"
                    }
                fi
            done
        fi
    else
        echo -e "${YELLOW}No configuration file found.${NC}"

        # Default Rails setup if no config
        if [ -f "Gemfile" ] && grep -q "rails" "Gemfile" 2>/dev/null; then
            echo -e "${GREEN}Detected Rails project. Running default setup...${NC}"

            if command -v bundle &> /dev/null; then
                echo -e "${BLUE}Running: bundle install${NC}"
                bundle install
            fi

            if [ -f "yarn.lock" ] && command -v yarn &> /dev/null; then
                echo -e "${BLUE}Running: yarn install${NC}"
                yarn install
            elif [ -f "package-lock.json" ] && command -v npm &> /dev/null; then
                echo -e "${BLUE}Running: npm install${NC}"
                npm install
            fi

            if command -v bundle &> /dev/null; then
                echo -e "${BLUE}Running: rails db:setup${NC}"
                bundle exec rails db:create db:migrate db:seed 2>/dev/null || true

                echo -e "${BLUE}Running: rails assets:precompile${NC}"
                bundle exec rails assets:precompile 2>/dev/null || true
            fi
        fi
    fi

    # Check for existing session info to reuse port
    SESSION_INFO="$WORKTREE_PATH/.claude-session"
    if [ "$REUSE_WORKTREE" = true ] && [ -f "$SESSION_INFO" ]; then
        # Try to use existing port
        EXISTING_PORT=$(grep "^PORT=" "$SESSION_INFO" 2>/dev/null | cut -d'=' -f2)
        if [ -n "$EXISTING_PORT" ] && ! lsof -i:$EXISTING_PORT >/dev/null 2>&1; then
            echo -e "${GREEN}Reusing existing port: $EXISTING_PORT${NC}"
            PORT=$EXISTING_PORT
        else
            echo -e "${YELLOW}Previous port $EXISTING_PORT is in use or invalid, finding new port...${NC}"
            PORT=$(find_available_port)
            echo -e "${GREEN}Using new port: $PORT${NC}"
        fi
    else
        # Find available port for new worktree
        echo -e "${GREEN}Finding available port...${NC}"
        PORT=$(find_available_port)
        echo -e "${GREEN}Using port: $PORT${NC}"
    fi

    # Register the port
    register_port "$PORT" "$WORKTREE_NAME" "$WORKTREE_PATH"

    # Create session info file
    SESSION_INFO="$WORKTREE_PATH/.claude-session"
    cat > "$SESSION_INFO" << EOF
WORKTREE_NAME=$WORKTREE_NAME
PORT=$PORT
STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BRANCH=$BRANCH_TO_USE
REPO=$REPO_NAME
DB_TYPE=$DB_TYPE
DB_NAME=$NEW_DB_NAME
DB_CREATED=$DB_CREATED
EOF
    
    # Register session with database info
    if [ "$DB_CREATED" = true ]; then
        register_session "$WORKTREE_NAME" "$WORKTREE_PATH" "$PORT" "{\"type\": \"$DB_TYPE\", \"name\": \"$NEW_DB_NAME\"}"
    else
        register_session "$WORKTREE_NAME" "$WORKTREE_PATH" "$PORT" "null"
    fi

    # Get server command from config
    SERVER_CMD=$(get_config_value "server_command" "")

    # If no server command, try to detect
    if [ -z "$SERVER_CMD" ]; then
        if [ -f "Procfile.dev" ] && command -v foreman &> /dev/null; then
            SERVER_CMD="foreman start -f Procfile.dev"
        elif [ -f "Procfile" ] && command -v foreman &> /dev/null; then
            SERVER_CMD="foreman start"
        elif [ -f "package.json" ] && grep -q "\"dev\"" "package.json" 2>/dev/null; then
            SERVER_CMD="npm run dev"
        elif [ -f "Gemfile" ] && grep -q "rails" "Gemfile" 2>/dev/null; then
            SERVER_CMD="bundle exec rails server"
        else
            SERVER_CMD="echo 'No server configured. Add server_command to .claude-worktree.yml'"
        fi
    fi

    # Append port to server command
    if [[ "$SERVER_CMD" =~ (foreman|rails|npm|yarn|python|node) ]] && [[ ! "$SERVER_CMD" =~ -p ]]; then
        if [[ "$SERVER_CMD" =~ foreman ]]; then
            SERVER_CMD="$SERVER_CMD -p $PORT"
        elif [[ "$SERVER_CMD" =~ rails ]]; then
            SERVER_CMD="$SERVER_CMD -p $PORT"
        elif [[ "$SERVER_CMD" =~ (npm|yarn).*(dev|start) ]]; then
            SERVER_CMD="$SERVER_CMD -- --port $PORT"
        elif [[ "$SERVER_CMD" =~ python.*manage.py.*runserver ]]; then
            SERVER_CMD="$SERVER_CMD $PORT"
        fi
    fi

    # Get Claude command from config
    CLAUDE_BASE_CMD=$(get_config_value "claude_command" "claude")
    if [ -z "$CLAUDE_BASE_CMD" ]; then
        CLAUDE_BASE_CMD="claude"
    fi
    
    # Test if the permissions flag is supported
    if $CLAUDE_BASE_CMD --help 2>&1 | grep -q "dangerously-skip-permissions"; then
        CLAUDE_CMD="$CLAUDE_BASE_CMD --dangerously-skip-permissions"
    else
        CLAUDE_CMD="$CLAUDE_BASE_CMD"
    fi

    # Create a cleanup function
    cleanup() {
        echo -e "\n${YELLOW}Cleaning up...${NC}"

        if [ "$SERVER_PID" = "terminal" ]; then
            echo -e "${YELLOW}Server is running in a separate terminal window${NC}"
            echo -e "${YELLOW}Please close the server terminal window manually${NC}"
            # Still try to kill processes on the port
            lsof -ti:$PORT | xargs kill -9 2>/dev/null || true
        elif [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
            echo -e "${YELLOW}Stopping server (PID: $SERVER_PID)...${NC}"
            kill -TERM -$SERVER_PID 2>/dev/null || kill -TERM $SERVER_PID 2>/dev/null
            sleep 2
            kill -0 "$SERVER_PID" 2>/dev/null && kill -KILL -$SERVER_PID 2>/dev/null
        fi

        # Always try to clean up processes on the port
        lsof -ti:$PORT | xargs kill -9 2>/dev/null || true

        unregister_port "$PORT"
        
        # Clean up database if it was created for this session
        if [ -f "$SESSION_INFO" ]; then
            local db_created=$(grep "^DB_CREATED=" "$SESSION_INFO" 2>/dev/null | cut -d'=' -f2)
            local db_type=$(grep "^DB_TYPE=" "$SESSION_INFO" 2>/dev/null | cut -d'=' -f2)
            local db_name=$(grep "^DB_NAME=" "$SESSION_INFO" 2>/dev/null | cut -d'=' -f2)
            
            if [ "$db_created" = "true" ] && [ -n "$db_type" ] && [ -n "$db_name" ]; then
                echo -e "${BLUE}Database cleanup options:${NC}"
                echo "1) Keep database for later use"
                echo "2) Drop database"
                echo "3) Skip (decide later)"
                
                read -r -p "Enter choice (1-3): " db_choice
                
                case $db_choice in
                    2)
                        drop_database "$db_type" "$db_name"
                        echo -e "${GREEN}Database dropped${NC}"
                        ;;
                    1)
                        echo -e "${GREEN}Database '$db_name' preserved for later use${NC}"
                        ;;
                    *)
                        echo -e "${YELLOW}Database '$db_name' left as-is${NC}"
                        ;;
                esac
            fi
        fi
        
        # Unregister session
        unregister_session "$WORKTREE_NAME"
        
        rm -f "$SESSION_INFO"

        # Offer post-session options
        echo -e "\n${CYAN}═══════════════════════════════════════════${NC}"
        echo -e "${CYAN}    Session Complete - What Next?${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════${NC}"
        
        # Check if there are any changes
        if [ -n "$(git status --porcelain)" ] || [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/$BRANCH_TO_USE 2>/dev/null || echo 'none')" ]; then
            echo -e "${BLUE}You have uncommitted changes or unpushed commits.${NC}"
            echo -e "\n${BLUE}Choose an option:${NC}"
            echo "1) Create a PR using Claude (recommended)"
            echo "2) Push changes to branch '$BRANCH_TO_USE'"
            echo "3) Leave everything as-is (come back later)"
            echo "4) Skip"
            
            read -r -p "Enter choice (1-4): " exit_choice
            
            case $exit_choice in
                1)
                    echo -e "\n${GREEN}Creating PR with Claude...${NC}"
                    cd "$WORKTREE_PATH"
                    $CLAUDE_CMD -c -p "create a PR" || {
                        echo -e "${YELLOW}Claude PR creation ended${NC}"
                    }
                    ;;
                2)
                    echo -e "\n${GREEN}Pushing changes to branch '$BRANCH_TO_USE'...${NC}"
                    cd "$WORKTREE_PATH"
                    git push -u origin "$BRANCH_TO_USE" || {
                        echo -e "${YELLOW}Push failed. You can push manually later.${NC}"
                    }
                    ;;
                3)
                    echo -e "\n${GREEN}Worktree preserved at: $WORKTREE_PATH${NC}"
                    echo -e "${BLUE}To resume later, run:${NC}"
                    echo -e "  cd $WORKTREE_PATH"
                    echo -e "  claude-worktree"
                    ;;
                *)
                    ;;
            esac
        else
            echo -e "${GREEN}No changes detected. Worktree clean.${NC}"
        fi
        
        echo -e "\n${CYAN}───────────────────────────────────────────${NC}"
        echo -e "${GREEN}✓ Cleanup complete${NC}"
        echo -e "${BLUE}Worktree location:${NC} $WORKTREE_PATH"
        echo -e "${CYAN}───────────────────────────────────────────${NC}"
    }

    trap cleanup EXIT INT TERM

    # Export environment variables
    export CLAUDE_WORKTREE_NAME="$WORKTREE_NAME"
    export CLAUDE_WORKTREE_PORT="$PORT"
    export CLAUDE_WORKTREE_PATH="$WORKTREE_PATH"
    export CLAUDE_WORKTREE_BRANCH="$BRANCH_TO_USE"

    # Create log file for server output
    SERVER_LOG="$WORKTREE_PATH/.claude-server.log"
    echo "Starting server at $(date)" > "$SERVER_LOG"
    
    # Start the server
    echo -e "${CYAN}───────────────────────────────────────────${NC}"
    echo -e "${GREEN}Starting server...${NC}"
    echo -e "${BLUE}Command: $SERVER_CMD${NC}"
    
    # Check if we can open a new terminal window
    if [[ "$OSTYPE" == "darwin"* ]] && command -v osascript &> /dev/null; then
        # Check if iTerm is available
        if osascript -e 'tell application "System Events" to exists application process "iTerm"' &> /dev/null || \
           osascript -e 'tell application "Finder" to exists application file "iTerm" of folder "Applications" of startup disk' &> /dev/null; then
            # iTerm is available - use it with custom title
            echo -e "${GREEN}Opening server in new iTerm window...${NC}"
            echo -e "${BLUE}Server will run in: iTerm.app${NC}"
            osascript -e "
            tell application \"iTerm\"
                activate
                create window with default profile
                tell current session of current window
                    write text \"cd '$WORKTREE_PATH'\"
                    write text \"echo -e '\\033]0;Claude Worktree: $WORKTREE_NAME [$BRANCH_TO_USE]\\007'\"
                    write text \"echo 'Claude Worktree Server - $WORKTREE_NAME'\"
                    write text \"echo 'Branch: $BRANCH_TO_USE | Port: $PORT'\"
                    write text \"echo '========================'\"
                    write text \"export CLAUDE_WORKTREE_PORT=$PORT\"
                    write text \"$SERVER_CMD\"
                end tell
            end tell" &> /dev/null
        else
            # Fall back to Terminal.app
            echo -e "${GREEN}Opening server in new Terminal window...${NC}"
            echo -e "${BLUE}Server will run in: Terminal.app${NC}"
            osascript -e "
            tell application \"Terminal\"
                activate
                do script \"cd '$WORKTREE_PATH' && echo -e '\\033]0;Claude Worktree: $WORKTREE_NAME [$BRANCH_TO_USE]\\007' && echo 'Claude Worktree Server - $WORKTREE_NAME' && echo 'Branch: $BRANCH_TO_USE | Port: $PORT' && echo '========================' && export CLAUDE_WORKTREE_PORT=$PORT && $SERVER_CMD\"
            end tell" &> /dev/null
        fi
        
        # Wait for server to actually start and be ready
        echo -e "${YELLOW}Waiting for server to start in new window...${NC}"
        SERVER_PID="terminal"
        
        # Wait up to 30 seconds for server to be ready
        local wait_time=0
        local max_wait=30
        while [ $wait_time -lt $max_wait ]; do
            if lsof -i:$PORT >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Server is ready on port $PORT${NC}"
                break
            fi
            sleep 1
            ((wait_time++))
            if [ $((wait_time % 5)) -eq 0 ]; then
                echo -e "${YELLOW}Still waiting for server... (${wait_time}s)${NC}"
            fi
        done
        
        if [ $wait_time -eq $max_wait ]; then
            echo -e "${YELLOW}Warning: Server may not have started properly${NC}"
            echo -e "${YELLOW}Check the terminal window for error messages${NC}"
            echo -e "${YELLOW}You can continue anyway, but the server may not be accessible${NC}"
        fi
    else
        # Fallback - run in background with output to log file
        echo -e "${YELLOW}Starting server in background (logs: $SERVER_LOG)${NC}"
        echo -e "${YELLOW}To view logs, run: tail -f $SERVER_LOG${NC}"
        
        set -m
        nohup bash -c "cd '$WORKTREE_PATH' && $SERVER_CMD" >> "$SERVER_LOG" 2>&1 &
        SERVER_PID=$!
        set +m
        
        echo -e "${YELLOW}Waiting for server to start...${NC}"
        sleep 5
        
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then
            echo -e "${RED}Warning: Server may have failed to start${NC}"
            echo -e "${YELLOW}Check the log file: $SERVER_LOG${NC}"
            echo -e "${YELLOW}Last few lines:${NC}"
            tail -n 10 "$SERVER_LOG"
        else
            echo -e "${GREEN}✓ Server started successfully (PID: $SERVER_PID)${NC}"
        fi
    fi

    # Display session information
    echo -e "${CYAN}───────────────────────────────────────────${NC}"
    echo -e "${GREEN}Claude Worktree Session Ready!${NC}"
    echo -e "${CYAN}───────────────────────────────────────────${NC}"
    echo -e "${BLUE}📂 Worktree:${NC} $WORKTREE_NAME"
    echo -e "${BLUE}📍 Location:${NC} $WORKTREE_PATH"
    echo -e "${BLUE}🌿 Branch:${NC} $BRANCH_TO_USE"
    echo -e "${BLUE}🚀 Server URL:${NC} http://localhost:$PORT"
    echo -e "${CYAN}───────────────────────────────────────────${NC}"

    # Check if Claude is available
    if ! command -v "$CLAUDE_BASE_CMD" &> /dev/null; then
        echo -e "${RED}Warning: '$CLAUDE_BASE_CMD' command not found${NC}"
        echo -e "${YELLOW}Please ensure Claude Code is installed${NC}"
        echo -e "${YELLOW}Visit: https://github.com/anthropics/claude-code${NC}"
        echo ""
        echo -e "${YELLOW}Press Enter to continue anyway, or Ctrl+C to exit${NC}"
        read -r
    fi

    # Start Claude
    echo -e "\n${GREEN}Starting Claude...${NC}"
    echo -e "${BLUE}Command: $CLAUDE_CMD${NC}"
    echo -e "${YELLOW}Note: Use Ctrl+C to exit and trigger cleanup${NC}"
    echo -e "${CYAN}───────────────────────────────────────────${NC}"
    
    # Change to worktree directory for Claude
    cd "$WORKTREE_PATH"
    
    # Temporarily disable exit on error for Claude command
    set +e
    $CLAUDE_CMD
    claude_exit_code=$?
    set -e
    
    if [ $claude_exit_code -ne 0 ]; then
        echo -e "${YELLOW}Claude exited with code $claude_exit_code${NC}"
        if [ $claude_exit_code -eq 127 ]; then
            echo -e "${RED}Error: Claude command not found. Please ensure Claude Code is installed.${NC}"
            echo -e "${YELLOW}Visit: https://github.com/anthropics/claude-code${NC}"
        fi
        echo -e "${YELLOW}Press Enter to continue with cleanup...${NC}"
        read -r
    else
        echo -e "${GREEN}Claude session ended normally${NC}"
    fi
}

# Run main function
main "$@"
