import { cacheExchange, Client, fetchExchange } from "urql";

const url =
  process.env.NEXT_PUBLIC_SUBGRAPH_URL ??
  "https://api.studio.thegraph.com/query/0/prediction-market/version/latest";

export const subgraphClient = new Client({
  url,
  exchanges: [cacheExchange, fetchExchange],
  fetchOptions: { cache: "no-store" },
});
