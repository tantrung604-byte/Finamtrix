# FastMoss CORS Proxy

Trình duyệt chặn gọi trực tiếp `openapi.fastmoss.com` (không có CORS header), nên bản **web** cần một proxy nhỏ. Proxy cũng **giấu Client Secret ở server** — web client không chứa secret.

Có 2 phương án, chọn 1:

## Phương án A — Cloudflare Worker (khuyên dùng, miễn phí)

```powershell
cd proxy/cloudflare-worker
npm i -g wrangler
wrangler login
wrangler secret put FASTMOSS_APP_SECRET   # dán Client Secret khi được hỏi
wrangler secret put FASTMOSS_APP_ID       # nhập: finmatrix
wrangler deploy
# → nhận URL dạng https://fastmoss-proxy.<account>.workers.dev
```

## Phương án B — Supabase Edge Function

```powershell
# cần Supabase CLI + project đã link
supabase functions deploy fastmoss-proxy --no-verify-jwt
supabase secrets set FASTMOSS_APP_SECRET=<client_secret> FASTMOSS_APP_ID=finmatrix
# → URL: https://<project>.supabase.co/functions/v1/fastmoss-proxy
```

## Build web dùng proxy

```powershell
flutter build web --release --dart-define=FASTMOSS_PROXY_URL=<URL ở trên>
```

Khi `FASTMOSS_PROXY_URL` được đặt, app gửi request **không kèm credentials** — proxy tự chèn `Authorization` + `access-key` phía server. Không đặt biến này thì app gọi thẳng FastMoss như cũ (Android/iOS/desktop).

## Test proxy sau khi deploy

```powershell
curl -X POST "<PROXY_URL>/product/v1/rank/topSelling" -H "Content-Type: application/json" -d '{\"filter\":{\"region\":\"VN\",\"date_info\":{\"type\":\"day\",\"value\":\"2026-07-11\"}},\"orderby\":[{\"field\":\"gmv\",\"order\":\"desc\"}],\"page\":1,\"pagesize\":1}'
# Kỳ vọng: {"code":0,"data":{...}}
```

## Bảo mật
- Proxy chỉ cho phép 4 endpoint ranking đang dùng (whitelist) — không phải open proxy.
- Response được cache 30 phút (dữ liệu FastMoss đổi 1 lần/ngày).
- Nếu có domain web riêng, đổi `Access-Control-Allow-Origin: *` thành domain đó.

