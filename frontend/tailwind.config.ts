import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // Proposal state badges (mirrors OZ Governor.ProposalState enum).
        state: {
          pending: "#9ca3af",
          active: "#2563eb",
          canceled: "#737373",
          defeated: "#dc2626",
          succeeded: "#16a34a",
          queued: "#f59e0b",
          expired: "#a3a3a3",
          executed: "#0d9488",
        },
      },
    },
  },
  plugins: [],
};

export default config;
