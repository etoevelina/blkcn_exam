"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { Toaster } from "react-hot-toast";
import { Provider as UrqlProvider } from "urql";
import { WagmiProvider } from "wagmi";

import { subgraphClient } from "@/lib/subgraph";
import { wagmiConfig } from "@/lib/wagmi";

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            staleTime: 30_000,
            refetchOnWindowFocus: false,
          },
        },
      }),
  );

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <UrqlProvider value={subgraphClient}>
          {children}
          <Toaster position="bottom-right" />
        </UrqlProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
