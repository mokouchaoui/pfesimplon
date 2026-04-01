// =============================================================================
// frontend/app/page.js
// -----------------------------------------------------------------------------
// The main (and only) page of the helpdesk application.
// Renders the ticket creation form and the list of existing tickets.
// Runs in the browser as a React client component ("use client" directive).
// All API calls go to /api/* which is intercepted by the proxy in route.js
// and forwarded server-side to the Flask backend — the browser never contacts
// the backend directly.
// =============================================================================

"use client";  // Marks this as a Client Component — runs in the browser with React hooks

import { useEffect, useState } from "react";

// API base path — relative URL so it always hits the same server the page was loaded from.
// Next.js routes /api/* to frontend/app/api/[...path]/route.js which proxies to Flask.
const API = "/api";

export default function Page() {
  const [tickets, setTickets] = useState([]);      // List of tickets fetched from backend
  const [title, setTitle] = useState("");          // Controlled input: ticket title
  const [description, setDescription] = useState(""); // Controlled input: ticket description

  // Fetches all tickets from the backend and updates state.
  // cache: "no-store" disables Next.js fetch caching so we always get fresh data.
  async function loadTickets() {
    const res = await fetch(`${API}/tickets`, { cache: "no-store" });
    const data = await res.json();
    setTickets(data);
  }

  // Handles the form submission — creates a new ticket then reloads the list.
  async function submit(e) {
    e.preventDefault();  // Prevent default browser form navigation
    await fetch(`${API}/tickets`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title, description })
    });
    setTitle("");          // Reset form fields after submission
    setDescription("");
    loadTickets();         // Refresh the ticket list
  }

  // Load tickets once when the component first mounts (page load).
  useEffect(() => {
    loadTickets();
  }, []);

  return (
    <main style={{ maxWidth: 780, margin: "40px auto", padding: 20 }}>
      <h1 style={{ marginTop: 0 }}>Helpdesk</h1>

      {/* Ticket creation form */}
      <form onSubmit={submit} style={{ display: "grid", gap: 10, marginBottom: 24 }}>
        <input
          placeholder="Ticket title"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          required
          style={{ padding: 10, borderRadius: 8, border: "1px solid #ccd5e1" }}
        />
        <textarea
          placeholder="Description"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          rows={4}
          style={{ padding: 10, borderRadius: 8, border: "1px solid #ccd5e1" }}
        />
        <button type="submit" style={{ padding: "10px 14px", borderRadius: 8, border: 0, background: "#0f172a", color: "white" }}>
          Create Ticket test
        </button>
      </form>

      {/* Ticket list — renders each ticket as a card */}
      <section style={{ display: "grid", gap: 10 }}>
        {tickets.map((t) => (
          <article key={t.id} style={{ background: "white", padding: 12, borderRadius: 10, border: "1px solid #e5e7eb" }}>
            <strong>{t.title}</strong>
            <p style={{ margin: "8px 0" }}>{t.description || "No description"}</p>
            <small>Status: {t.status}</small>
          </article>
        ))}
        {tickets.length === 0 && <p>No tickets yet.</p>}
      </section>
    </main>
  );
}
