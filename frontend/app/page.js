"use client";

import { useEffect, useState } from "react";

const API = "/api";

export default function Page() {
  const [tickets, setTickets] = useState([]);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");

  async function loadTickets() {
    const res = await fetch(`${API}/tickets`, { cache: "no-store" });
    const data = await res.json();
    setTickets(data);
  }

  async function submit(e) {
    e.preventDefault();
    await fetch(`${API}/tickets`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title, description })
    });
    setTitle("");
    setDescription("");
    loadTickets();
  }

  useEffect(() => {
    loadTickets();
  }, []);

  return (
    <main style={{ maxWidth: 780, margin: "40px auto", padding: 20 }}>
      <h1 style={{ marginTop: 0 }}>Helpdesk</h1>
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
          Create Ticket
        </button>
      </form>

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
