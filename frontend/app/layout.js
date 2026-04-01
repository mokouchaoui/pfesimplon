// =============================================================================
// frontend/app/layout.js
// -----------------------------------------------------------------------------
// The root layout — wraps every page in the application.
// Next.js App Router requires this file to define the HTML shell.
// All pages (page.js) are rendered inside the {children} slot.
// =============================================================================

// Metadata is used by Next.js to set the <title> and <meta description> tags.
export const metadata = {
  title: "Helpdesk",
  description: "Minimal Helpdesk App"
};

// RootLayout wraps the entire app with the HTML and body tags.
// Inline styles keep the project dependency-free (no CSS framework needed).
export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body style={{ margin: 0, fontFamily: "ui-sans-serif, system-ui", background: "#f5f7fb" }}>
        {children}  {/* page.js content is rendered here */}
      </body>
    </html>
  );
}
