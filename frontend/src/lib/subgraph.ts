import { cacheExchange, Client, fetchExchange } from "urql";

const url =
  process.env.NEXT_PUBLIC_SUBGRAPH_URL ??
  "https://api.studio.thegraph.com/query/0/prediction-market/version/latest";

export const subgraphClient = new Client({
  url,
  exchanges: [cacheExchange, fetchExchange],
  // On the server (RSC fetch), urql will use the global `fetch` polyfilled
  // by Next.js; on the client, it uses the browser fetch. Either way we
  // disable Next.js's internal cache so live-data pages don't stale.
  fetchOptions: { cache: "no-store" },
});
