import "./globals.css";
import { themeInitScript } from "./lib/theme";

export const metadata = {
  title: "Vendra Admin",
  description: "Admin control panel for Vendra Multi-Vendor Digital Marketplace",
};

export default function RootLayout({ children }) {
  return (
    // The init script sets the .dark class before hydration, so <html> legitimately differs from the server render
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeInitScript }} />
        <link
          href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />
        <link
          href="https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@20..48,100..700,0..1,-50..200&display=swap"
          rel="stylesheet"
        />
      </head>
      <body className="antialiased">{children}</body>
    </html>
  );
}
