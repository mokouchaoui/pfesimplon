const BACKEND = process.env.BACKEND_URL || "http://backend:5000";

export async function GET(request, { params }) {
  const { path } = await params;
  const res = await fetch(`${BACKEND}/${path.join("/")}`, { cache: "no-store" });
  const data = await res.json();
  return Response.json(data, { status: res.status });
}

export async function POST(request, { params }) {
  const { path } = await params;
  const body = await request.json().catch(() => ({}));
  const res = await fetch(`${BACKEND}/${path.join("/")}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  return Response.json(data, { status: res.status });
}
