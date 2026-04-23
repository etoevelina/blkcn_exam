## BChT2 Prediction Market — repo-root convenience targets.
##
## Usage:
##   make help                  # list targets
##   make install               # forge install + pnpm install
##   make build                 # forge build + frontend build + subgraph build
##   make test                  # forge test
##   make coverage              # forge coverage with line-summary
##   make slither               # local slither (must be installed)
##   make deploy-sepolia        # script/Deploy.s.sol against Arbitrum Sepolia
##   make verify-sepolia        # script/Verify.s.sol (read-only)
##   make subgraph-deploy       # graph deploy --studio
##   make abi-sync              # copy ABIs from out/ into subgraph/abis/

SHELL := /usr/bin/env bash

.PHONY: help install build test coverage slither deploy-sepolia verify-sepolia subgraph-deploy abi-sync clean

help:
	@awk -F': ' '/^## / { sub(/^## /, "", $$0); print }' Makefile

install:
	forge install --no-git foundry-rs/forge-std@v1.9.4 || true
	forge install --no-git OpenZeppelin/openzeppelin-contracts@v5.0.2 || true
	forge install --no-git OpenZeppelin/openzeppelin-contracts-upgradeable@v5.0.2 || true
	forge install --no-git smartcontractkit/chainlink-brownie-contracts@v1.2.0 || true
	pnpm install
	(cd subgraph && pnpm install)
	(cd frontend && pnpm install)

build:
	forge build --sizes
	(cd subgraph && pnpm codegen && pnpm build)
	(cd frontend && pnpm build)

test:
	forge test -vvv

coverage:
	forge coverage --report summary --report lcov

slither:
	slither . --config-file slither.config.json --fail-on medium

deploy-sepolia:
	forge script script/Deploy.s.sol \
	    --rpc-url arbitrum_sepolia \
	    --private-key $$DEPLOYER_PRIVATE_KEY \
	    --broadcast --verify --etherscan-api-key $$ARBISCAN_API_KEY \
	    -vvv

verify-sepolia:
	forge script script/Verify.s.sol --rpc-url arbitrum_sepolia -vv

subgraph-deploy:
	(cd subgraph && pnpm deploy:studio)

abi-sync:
	@mkdir -p subgraph/abis frontend/src/lib/abi-json
	@for c in PredictionMarketFactory PredictionMarket OutcomeToken1155; do \
	    jq '.abi' out/$$c.sol/$$c.json > subgraph/abis/$$c.json; \
	    cp subgraph/abis/$$c.json frontend/src/lib/abi-json/$$c.json; \
	done
	@echo "ABIs synced."

clean:
	forge clean
	rm -rf subgraph/build subgraph/generated frontend/.next frontend/out
