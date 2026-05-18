import deployment from "../../../deployments/arbitrum-sepolia.json";

import type { Address } from "viem";

export interface ProtocolAddresses {
  collateralToken: Address;
  outcomeToken: Address;
  oracleAdapter: Address;
  feeVault: Address;
  governanceToken: Address;
  timelock: Address;
  governor: Address;
  factoryProxy: Address;
  factoryImpl: Address;
}

const empty: Address = "0x0000000000000000000000000000000000000000";

/** Resolves to the deployed address or `0x000…000` if not yet deployed. */
export const addresses: ProtocolAddresses = {
  collateralToken: (deployment.collateralToken as Address) ?? empty,
  outcomeToken:    (deployment.outcomeToken    as Address) ?? empty,
  oracleAdapter:   (deployment.oracleAdapter   as Address) ?? empty,
  feeVault:        (deployment.feeVault        as Address) ?? empty,
  governanceToken: (deployment.governanceToken as Address) ?? empty,
  timelock:        (deployment.timelock        as Address) ?? empty,
  governor:        (deployment.governor        as Address) ?? empty,
  factoryProxy:    (deployment.factoryProxy    as Address) ?? empty,
  factoryImpl:     (deployment.factoryImpl     as Address) ?? empty,
};

export function isDeployed(addr: Address): boolean {
  return addr !== empty;
}
