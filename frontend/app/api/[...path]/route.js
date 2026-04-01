// =============================================================================
// frontend/app/api/[...path]/route.js
// -----------------------------------------------------------------------------
// Server-side API proxy route — the most critical architectural file.
// Intercepts ALL requests to /api/* and forwards them to the Flask backend.
//
// WHY THIS EXISTS:
//   The Flask backend runs as a ClusterIP Kubernetes service (no public IP).
//   Its hostname "backend:5000" only exists inside the Kubernetes cluster.
//   A browser on a user's laptop cannot resolve "backend:5000" — it's not
//   a real internet address. So instead:
//     Browser → /api/tickets → Next.js server (inside cluster) → backend:5000
//   The Next.js pod CAN reach backend:5000 because it runs inside the cluster.
//
// The [...path] catch-all route matches /api/tickets, /api/health, etc.
// BACKEND_URL is set to "http://backend:5000" via Kubernetes ConfigMap.
// =============================================================================

// Read the backend URL from environment — defaults to cluster-internal DNS.
// In Kubernetes: injected from ConfigMap as BACKEND_URL=http://backend:5000
// In local Docker Compose: injected as BACKEND_URL=http://backend:5000
const BACKEND = process.env.BACKEND_URL || "http://backend:5000";

// Handles GET requests: /api/tickets → GET http://backend:5000/tickets
export async function GET(request, { params }) {
  const { path } = await params;  // path is an array, e.g. ["tickets"]
  const res = await fetch(`${BACKEND}/${path.join("/")}`, { cache: "no-store" });
  const data = await res.json();
  return Response.json(data, { status: res.status });  // Forward the status code too
}

// Handles POST requests: /api/tickets → POST http://backend:5000/tickets
export async function POST(request, { params }) {
  const { path } = await params;
  const body = await request.json().catch(() => ({}));  // Parse body safely
  const res = await fetch(`${BACKEND}/${path.join("/")}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),  // Forward the request body to Flask
  });
  const data = await res.json();
  return Response.json(data, { status: res.status });  // Forward Flask's response
}
