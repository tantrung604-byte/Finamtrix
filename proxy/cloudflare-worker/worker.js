/**
 * FastMoss Open API CORS proxy — Cloudflare Worker.
 *
 * Purpose:
 *   - Browsers block direct calls to openapi.fastmoss.com (no CORS headers).
 *   - This worker forwards the request server-side and adds CORS headers.
 *   - The FastMoss credentials stay HERE (worker secrets) — the web client
 *     never ships or stores the Client Secret.
 *
 * Deploy (2 phút):
 *   npm i -g wrangler
 *   wrangler login
 *   wrangler secret put FASTMOSS_APP_SECRET   # dán Client Secret
 *   wrangler secret put FASTMOSS_APP_ID       # ví dụ: finmatrix
 *   wrangler deploy
 *
 * Rồi build web với:
 *   flutter build web --release --dart-define=FASTMOSS_PROXY_URL=https://<worker>.workers.dev
 */

const UPSTREAM = 'https://openapi.fastmoss.com';

// Chỉ cho phép các endpoint ranking đã dùng trong app (an toàn hơn open proxy).
const ALLOWED_PATHS = [
  '/product/v1/rank/topSelling',
  '/product/v1/rank/fullyManaged',
  '/shop/v1/rank/topSelling',
  '/shop/v1/rank/fullyManaged',
];

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*', // có domain riêng thì thay bằng domain đó
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Accept',
  'Access-Control-Max-Age': '86400',
};

export default {
  async fetch(request, env) {
    // Preflight CORS.
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }
    if (request.method !== 'POST') {
      return json({ code: -1, message: 'POST only' }, 405);
    }

    const url = new URL(request.url);
    const path = url.pathname;
    if (!ALLOWED_PATHS.includes(path)) {
      return json({ code: -1, message: `path not allowed: ${path}` }, 404);
    }
    if (!env.FASTMOSS_APP_SECRET) {
      return json({ code: -1, message: 'FASTMOSS_APP_SECRET not configured' }, 500);
    }

    let body;
    try {
      body = await request.text();
    } catch (_) {
      return json({ code: -1, message: 'invalid body' }, 400);
    }

    const upstream = await fetch(`${UPSTREAM}${path}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': `Bearer ${env.FASTMOSS_APP_SECRET}`,
        ...(env.FASTMOSS_APP_ID ? { 'access-key': env.FASTMOSS_APP_ID } : {}),
      },
      body,
    });

    const text = await upstream.text();
    return new Response(text, {
      status: upstream.status,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'public, max-age=1800', // ranking đổi 1 lần/ngày → cache 30'
        ...CORS_HEADERS,
      },
    });
  },
};

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS_HEADERS },
  });
}

