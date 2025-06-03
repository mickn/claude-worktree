# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude Worktree Manager is a Bash-based tool that creates isolated Git worktrees for Claude Code sessions. It automates worktree creation, server management, port allocation, and integrates seamlessly with Claude Code workflows.

## Common Commands

### Development & Testing
```bash
# Run tests
./test.sh

# Install locally (for development)
./install.sh

# Create example repositories for testing
cd examples && ./create-all.sh

# Test the main script directly
./claude-worktree.sh [branch-name]
```

### Build & Release
```bash
# Create release tarball
make dist

# Clean build artifacts
make clean
```

## Architecture & Key Components

### Main Script Structure (claude-worktree.sh)
The script is organized into logical sections:
1. **Configuration & Constants**: Port ranges, session directory, config files
2. **Helper Functions**: Color output, error handling, dependency checks
3. **Core Functions**:
   - `find_available_port()`: Smart port allocation with conflict detection
   - `setup_worktree()`: Git worktree creation and initialization
   - `start_server()`: Server management with terminal window support
   - `register_session()`: JSON-based session tracking
   - `cleanup()`: Comprehensive cleanup with trap handlers
4. **Workflow Functions**: Post-session actions (PR creation, branch pushing)

### Session Management
- Sessions tracked in `~/.claude-worktree/sessions.json`
- Each session stores: worktree path, port, PID, server command
- Automatic cleanup of stale sessions on startup

### Configuration System
Projects use `.claude-worktree.yml` for customization:
- `setup_commands`: Commands run after worktree creation
- `server_command`: Command to start development server
- `port`: Default port (overridden if unavailable)
- `copy_dotfiles`: List of files to copy from parent

### Key Implementation Details

1. **Port Allocation**: Searches 3000-9999 range, checking both system ports and registered sessions
2. **Branch Handling**: Automatically creates new branches when conflicts detected
3. **Server Management**: Uses `caffeinate` on macOS to prevent sleep, opens in new terminal window
4. **Error Recovery**: Trap handlers ensure cleanup even on unexpected exit
5. **ZSH Integration**: Exports functions as `cw`, `cws`, `cwi` aliases

## Important Patterns

### Adding New Project Types
1. Create example YAML in `examples/`
2. Follow naming convention: `{framework}.claude-worktree.yml`
3. Test with `create-claude-worktree-repo.sh`

### Error Handling
- Always use `error_exit()` for fatal errors
- Clean up resources in reverse order of creation
- Check dependencies before operations

### Testing Changes
- Run `./test.sh` after modifications
- Test both new worktree creation and resuming existing worktrees
- Verify server management and port allocation
- Check cleanup behavior on various exit scenarios