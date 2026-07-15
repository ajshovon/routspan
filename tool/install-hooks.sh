#!/usr/bin/env bash
# Point git at the version-controlled hooks in .githooks/. Run this once after
# cloning. Unlike copying into .git/hooks, core.hooksPath keeps the hooks under
# version control so everyone gets the same checks.
#
# Usage: tool/install-hooks.sh
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

git config core.hooksPath .githooks
chmod +x .githooks/* 2>/dev/null || true

echo "✓ git hooks installed (core.hooksPath=.githooks)"
echo "  pre-commit : dart format check + analyze"
echo "  pre-push   : flutter test"
echo "  commit-msg : Conventional Commits"
echo ""
echo "Bypass any hook with --no-verify (CI still enforces the same checks)."
