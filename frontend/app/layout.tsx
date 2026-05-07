import type { Metadata } from "next";
import type { ReactNode } from "react";

import { Header } from "@/components/Header";
import { NetworkGuard } from "@/components/NetworkGuard";

import "./globals.css";
import { Providers } from "./providers";

export const metadata: Metadata = {
  title: "Prediction Market — BChT2",
  description: "Binary outcome prediction markets on Arbitrum Sepolia.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-neutral-950 text-neutral-100 antialiased">
        <Providers>
          <Header />
          <main className="mx-auto max-w-6xl px-4 py-8">
            <NetworkGuard>{children}</NetworkGuard>
          </main>
        </Providers>
      </body>
    </html>
  );
}
