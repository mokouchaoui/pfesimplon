export const metadata = {
  title: "Helpdesk",
  description: "Minimal Helpdesk App"
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body style={{ margin: 0, fontFamily: "ui-sans-serif, system-ui", background: "#f5f7fb" }}>
        {children}
      </body>
    </html>
  );
}
