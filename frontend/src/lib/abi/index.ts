export const erc20Abi = [
  { type: "function", name: "approve",   stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "allowance", stateMutability: "view",       inputs: [{ type: "address" }, { type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "balanceOf", stateMutability: "view",       inputs: [{ type: "address" }],                       outputs: [{ type: "uint256" }] },
  { type: "function", name: "decimals",  stateMutability: "view",       inputs: [],                                          outputs: [{ type: "uint8"  }] },
  { type: "function", name: "symbol",    stateMutability: "view",       inputs: [],                                          outputs: [{ type: "string" }] },
] as const;

export const outcomeTokenAbi = [
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "setApprovalForAll", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "bool" }], outputs: [] },
  { type: "function", name: "isApprovedForAll",  stateMutability: "view",       inputs: [{ type: "address" }, { type: "address" }], outputs: [{ type: "bool" }] },
] as const;

export const marketAbi = [
  { type: "function", name: "reserves",          stateMutability: "view", inputs: [], outputs: [{ name: "reserveYes", type: "uint128" }, { name: "reserveNo", type: "uint128" }] },
  { type: "function", name: "status",            stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "yesId",             stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "noId",              stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "tradingEndsAt",     stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "disputeEndsAt",     stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "winningOutcome",    stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "feeBps",            stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
  { type: "function", name: "totalSupply",       stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "balanceOf",         stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "getAmountOut",      stateMutability: "view", inputs: [{ type: "uint256" }, { type: "uint256" }, { type: "uint256" }], outputs: [{ type: "uint256" }] },
  {
    type: "function", name: "addLiquidity", stateMutability: "nonpayable",
    inputs: [{ name: "collateralIn", type: "uint256" }, { name: "minLpOut", type: "uint256" }, { name: "deadline", type: "uint256" }],
    outputs: [{ name: "lpMinted", type: "uint256" }, { name: "yesLeftover", type: "uint256" }, { name: "noLeftover", type: "uint256" }],
  },
  {
    type: "function", name: "removeLiquidity", stateMutability: "nonpayable",
    inputs: [{ name: "lpBurn", type: "uint256" }, { name: "minYesOut", type: "uint256" }, { name: "minNoOut", type: "uint256" }, { name: "deadline", type: "uint256" }],
    outputs: [{ name: "yesOut", type: "uint256" }, { name: "noOut", type: "uint256" }],
  },
  {
    type: "function", name: "swap", stateMutability: "nonpayable",
    inputs: [{ name: "outcomeIn", type: "uint256" }, { name: "outcomeOut", type: "uint256" }, { name: "amountIn", type: "uint256" }, { name: "minOut", type: "uint256" }, { name: "deadline", type: "uint256" }],
    outputs: [{ name: "amountOut", type: "uint256" }],
  },
  { type: "function", name: "mintCompleteSets",   stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [] },
  { type: "function", name: "redeemCompleteSets", stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [] },
  { type: "function", name: "claimWinnings",      stateMutability: "nonpayable", inputs: [],                    outputs: [{ type: "uint256" }] },
] as const;

export const governorAbi = [
  { type: "function", name: "state",            stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint8" }] },
  { type: "function", name: "votingDelay",      stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "votingPeriod",     stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "proposalThreshold",stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "quorum",           stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "proposalEta",      stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  {
    type: "function", name: "castVoteWithReason", stateMutability: "nonpayable",
    inputs: [{ name: "proposalId", type: "uint256" }, { name: "support", type: "uint8" }, { name: "reason", type: "string" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function", name: "castVote", stateMutability: "nonpayable",
    inputs: [{ name: "proposalId", type: "uint256" }, { name: "support", type: "uint8" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function", name: "queue", stateMutability: "nonpayable",
    inputs: [
      { name: "targets",  type: "address[]" },
      { name: "values",   type: "uint256[]" },
      { name: "calldatas",type: "bytes[]"   },
      { name: "descriptionHash", type: "bytes32" },
    ],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function", name: "execute", stateMutability: "payable",
    inputs: [
      { name: "targets",  type: "address[]" },
      { name: "values",   type: "uint256[]" },
      { name: "calldatas",type: "bytes[]"   },
      { name: "descriptionHash", type: "bytes32" },
    ],
    outputs: [{ type: "uint256" }],
  },
] as const;

export const governanceTokenAbi = [
  { type: "function", name: "balanceOf",     stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "getVotes",      stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "delegates",     stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "address" }] },
  { type: "function", name: "delegate",      stateMutability: "nonpayable", inputs: [{ name: "delegatee", type: "address" }], outputs: [] },
] as const;

export const timelockAbi = [
  { type: "function", name: "getMinDelay",  stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "hasRole",      stateMutability: "view", inputs: [{ type: "bytes32" }, { type: "address" }], outputs: [{ type: "bool" }] },
] as const;
