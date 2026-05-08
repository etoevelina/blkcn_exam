// Mirror of subgraph/queries/*.graphql as gql tagged-template literals so
// urql can co-locate the queries with the frontend hooks. Five queries,
// one per file in `subgraph/queries/`.

import { gql } from "urql";

export const ACTIVE_MARKETS = gql/* GraphQL */ `
  query ActiveMarkets($first: Int = 25, $skip: Int = 0) {
    markets(
      first: $first
      skip: $skip
      where: { status_in: [Open, Locked, Reported, Disputed] }
      orderBy: tradingEndsAt
      orderDirection: asc
    ) {
      id
      marketId
      questionId
      feeBps
      status
      tradingEndsAt
      disputeEndsAt
      reserveYes
      reserveNo
      totalLpSupply
      swapCount
      winningOutcome
      createdAt
    }
  }
`;

export const MARKET_DETAIL = gql/* GraphQL */ `
  query MarketDetail($id: ID!, $recent: Int = 20) {
    market(id: $id) {
      id
      marketId
      questionId
      oracleThreshold
      collateralToken
      outcomeToken
      yesId
      noId
      feeBps
      status
      tradingEndsAt
      disputeEndsAt
      reserveYes
      reserveNo
      totalLpSupply
      swapCount
      liquidityEventCount
      winningOutcome
      creator
      createdAt
      swaps(first: $recent, orderBy: timestamp, orderDirection: desc) {
        id
        trader {
          id
        }
        outcomeInId
        outcomeOutId
        amountIn
        amountOut
        feeAccrued
        timestamp
        transactionHash
      }
      liquidityEvents(first: $recent, orderBy: timestamp, orderDirection: desc) {
        id
        provider {
          id
        }
        kind
        collateralIn
        lpAmount
        yesAmount
        noAmount
        timestamp
        transactionHash
      }
    }
  }
`;

export const USER_PORTFOLIO = gql/* GraphQL */ `
  query UserPortfolio($user: Bytes!, $first: Int = 50) {
    userPositions(
      first: $first
      where: { user: $user }
      orderBy: lastUpdatedAt
      orderDirection: desc
    ) {
      id
      yesBalance
      noBalance
      lpBalance
      collateralClaimed
      lastUpdatedAt
      market {
        id
        marketId
        questionId
        status
        winningOutcome
        reserveYes
        reserveNo
        totalLpSupply
        tradingEndsAt
      }
    }
  }
`;

export const ACTIVE_PROPOSALS = gql/* GraphQL */ `
  query ActiveProposals($first: Int = 50) {
    proposals(
      first: $first
      where: { statusSnapshot_in: [Pending, Active, Succeeded, Queued] }
      orderBy: createdAt
      orderDirection: desc
    ) {
      id
      proposer
      description
      voteStart
      voteEnd
      forVotes
      againstVotes
      abstainVotes
      statusSnapshot
      eta
      queuedAt
      canceledAt
      executedAt
      createdAt
      votes(first: 5, orderBy: timestamp, orderDirection: desc) {
        voter
        support
        weight
        reason
        timestamp
      }
    }
  }
`;

export const MARKET_STATS = gql/* GraphQL */ `
  query MarketStats($first: Int = 10) {
    markets(
      first: $first
      orderBy: swapCount
      orderDirection: desc
      where: { status_in: [Open, Locked, Reported, Finalized] }
    ) {
      id
      marketId
      questionId
      status
      swapCount
      liquidityEventCount
      totalLpSupply
      reserveYes
      reserveNo
      feeBps
      tradingEndsAt
    }
    traders(first: 5, orderBy: totalVolumeIn, orderDirection: desc) {
      id
      swapCount
      totalVolumeIn
      totalFeesPaid
    }
  }
`;
