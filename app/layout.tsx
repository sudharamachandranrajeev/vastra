import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Vastra — A world of good finds",
  description: "Discover fashion, beauty, and the people behind them. Build your personal edit with product-link imports, seller discovery, and thoughtful comparisons.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  );
}
