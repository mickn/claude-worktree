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
