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
