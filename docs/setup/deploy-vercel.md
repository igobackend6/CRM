# Deploying the Sales CRM API on Vercel (testing)

Good for testing: no server to look after, automatic HTTPS. Move to the VPS (`deploy-vps.md`)
when you need what Vercel can't do (see "Limits").

Files used: `backend/api/index.py`, `backend/.vercelignore` (no vercel.json: the FastAPI preset routes requests itself; a rewrite made every path 404).
Nothing in the app code changes; local running (`uvicorn app.main:app`) is unchanged.

## Steps

1. **Commit and push** the code to GitHub (`igobackend6/CRM`). Vercel builds from GitHub.
2. Sign in at vercel.com with GitHub -> **Add New > Project** -> import `CRM`.
3. **Root Directory: `backend`** (important). Framework preset: *Other*. Leave build/output blank.
4. **Environment Variables** (Settings > Environment Variables, for Production and Preview):
   `ENVIRONMENT=production`, `LOG_LEVEL=INFO`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
   `SUPABASE_ANON_KEY`, `SUPABASE_JWT_SECRET` (same values as `backend/.env`).
   The service-role key lives only here, never in the app or Git.
5. Settings > Functions > set the **Region** closest to your Supabase project.
6. **Deploy.** Open `https://<your-project>.vercel.app/health` -> `{"status":"ok"}`.
   (With `ENVIRONMENT=production`, `/docs` and `/openapi.json` are off by design.)
7. Put the address in the app and rebuild the APK:
   `mobile/env/.env.staging` (or `.env.production`): `API_BASE_URL=https://<your-project>.vercel.app`
   then `flutter build apk --dart-define=FLAVOR=staging`. It works from anywhere, with this PC off.

## Updating
Push to GitHub: Vercel redeploys by itself (about a minute). Backend changes reach every phone
immediately; app screen changes still need a new APK.

## Limits (why the VPS later)
- Request body about 4.5 MB: lead documents above that fail (the backend allows 25 MB).
- No background scheduler (no jobs registered today); timed jobs would need Vercel Cron.
- Rate limiting is in memory, per instance: weaker than on a single server.
- Function time limit (about 10 s on the free plan) and slower first request after idle.
- Hobby plan is non-commercial; a company should use Pro.
- Not yet deployed or tested from here: check `/health`, then sign in on one phone.
