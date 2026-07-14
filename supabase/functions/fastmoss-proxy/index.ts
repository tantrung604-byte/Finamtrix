// FastMoss Open API CORS proxy — Supabase Edge Function (Deno).
//
// Deploy:
//   supabase functions deploy fastmoss-proxy --no-verify-jwt
//   supabase secrets set FASTMOSS_APP_SECRET=<client_secret> FASTMOSS_APP_ID=finmatrix
//
// Gọi từ web: POST https://<project>.supabase.co/functions/v1/fastmoss-proxy/product/v1/rank/topSelling
// Build web với:
//   flutter build web --release --dart-define=FASTMOSS_PROXY_URL=https://<project>.supabase.co/functions/v1/fastmoss-proxy

const UPSTREAM = 'https://openapi.fastmoss.com';

const ALLOWED_PATHS = [
  '/product/v1/rank/topSelling',
  '/product/v1/rank/fullyManaged',
  '/shop/v1/rank/topSelling',
  '/shop/v1/rank/fullyManaged',
];

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Accept, Authorization, apikey, x-client-info',
  'Access-Control-Max-Age': '86400',
};

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS_HEADERS },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== 'POST') return json({ code: -1, message: 'POST only' }, 405);

  // Path sau tên function: /fastmoss-proxy/<upstream path>
  const url = new URL(req.url);
  const path = url.pathname.replace(/^\/functions\/v1\/fastmoss-proxy/, '')
      .replace(/^\/fastmoss-proxy/, '');
  if (!ALLOWED_PATHS.includes(path)) {
    return json({ code: -1, message: `path not allowed: ${path}` }, 404);
  }

  const secret = Deno.env.get('FASTMOSS_APP_SECRET') ?? '';
  const appId = Deno.env.get('FASTMOSS_APP_ID') ?? '';
  if (!secret) return json({ code: -1, message: 'FASTMOSS_APP_SECRET not configured' }, 500);

  const body = await req.text();
  const upstream = await fetch(`${UPSTREAM}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': `Bearer ${secret}`,
      ...(appId ? { 'access-key': appId } : {}),
    },
    body,
  });

  const text = await upstream.text();
  return new Response(text, {
    status: upstream.status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'public, max-age=1800',
      ...CORS_HEADERS,
    },
  });
});

