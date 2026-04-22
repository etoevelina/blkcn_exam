#!/usr/bin/env bash
# Pre-commit hook. Install with:
#
#     pnpm install            # husky's prepare script will create .husky/
#     cp scripts/pre-commit.sh .husky/pre-commit
#     chmod +x .husky/pre-commit
#
# (We commit it as scripts/pre-commit.sh because /.husky/ is protected
# in some agent sandboxes and would otherwise blow up here.)

set -e

echo "→ forge fmt --check"
forge fmt --check

echo "→ solhint"
pnpm exec solhint 'src/**/*.sol' 'script/**/*.sol' 'test/**/*.sol'

echo "→ frontend prettier --check"
(cd frontend && pnpm format:check)

echo "→ frontend eslint"
(cd frontend && pnpm lint)
