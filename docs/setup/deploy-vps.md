# Deploying the Sales CRM API on a small VPS

The app has three parts. Two are already online; this guide puts the third online.

| Part | Where it runs |
|---|---|
| Database, login, file storage, `call-sync` function | Supabase (already hosted) |
| **FastAPI backend** (`backend/`) | **this guide: your VPS** |
| Flutter app | each phone (APK) |

After this, the app no longer needs your PC, your Wi-Fi or a USB cable.

## 0. What you need

- A VPS: Ubuntu 22.04 or 24.04, 1 vCPU, 1–2 GB RAM, 20 GB disk is plenty (Hetzner, DigitalOcean, Vultr, Contabo, an Azure/AWS small VM...). Note its **public IP**.
- A web address for it (HTTPS is required — release Android apps refuse plain `http://`):
  - **With a domain:** add an `A` record, e.g. `api.yourcompany.com` -> the VPS IP.
  - **Without a domain:** use `<ip-with-dashes>.sslip.io`, e.g. IP `203.0.113.10` -> `203-0-113-10.sslip.io`. It resolves to your IP with no setup, and Caddy gets a real certificate for it.
- The values from your `backend/.env` (Supabase URL, service-role key, anon key, JWT secret).
- The code on the server (step 3).

## 1. First login and basic safety

```bash
ssh root@YOUR_SERVER_IP
adduser crm                       # a normal user; pick a strong password
usermod -aG sudo crm
rsync --archive --chown=crm:crm ~/.ssh /home/crm      # lets you ssh in as crm with the same key
```

Open a second terminal and check `ssh crm@YOUR_SERVER_IP` works, then continue as `crm`.

Firewall — only SSH, HTTP and HTTPS are open:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

(The API itself, port 8000, is never opened to the internet; only Caddy can reach it.)

## 2. Install Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker crm
exit            # log out and back in so the group applies
ssh crm@YOUR_SERVER_IP
docker --version && docker compose version
```

## 3. Put the code on the server

Pick one.

**A. From GitHub** (repo `igobackend6/CRM`). Everything must be **committed and pushed first** from your PC, or the server gets old code:

```bash
git clone https://github.com/igobackend6/CRM.git
cd CRM
```

**B. Copy from your PC** (no GitHub needed). On your PC, in PowerShell, from `E:\CRM`:

```powershell
scp -r backend deploy crm@YOUR_SERVER_IP:~/CRM/
```

(create the folder first with `ssh crm@YOUR_SERVER_IP "mkdir -p ~/CRM"`; do **not** copy `backend\.env` or `backend\.venv`).

## 4. Configure

```bash
cd ~/CRM/deploy
cp .env.example .env
nano .env
```

Fill in `DOMAIN` and the Supabase values (same ones as your PC's `backend/.env`). Save with Ctrl+O, Enter, Ctrl+X. Then lock the file down:

```bash
chmod 600 .env
```

## 5. Start it

```bash
docker compose up -d --build
docker compose ps          # both "api" and "caddy" should be Up (api: healthy)
docker compose logs -f api # Ctrl+C to leave; look for "Application startup complete"
```

The first start takes a minute: Caddy requests the HTTPS certificate (ports 80/443 must be reachable and the domain must already point at the server).

## 6. Check it from outside

From your PC or phone browser:

```
https://YOUR_DOMAIN/health        ->  {"status":"ok"}
```

If it doesn't load: `docker compose logs caddy` (certificate problems are almost always DNS not pointing at the server yet, or port 80/443 blocked by the provider's firewall).

## 7. Point the app at it and build the APK (on your PC)

1. Edit `mobile/env/.env.production` (and `.env.staging` if you still use it):
   ```
   API_BASE_URL=https://YOUR_DOMAIN
   ```
2. Build:
   ```powershell
   cd E:\CRM\mobile
   flutter build apk --dart-define=FLAVOR=production
   ```
3. The APK is `mobile\build\app\outputs\flutter-apk\app-release.apk`. Send it to your manager (WhatsApp / Drive / email), who installs it and signs in. No Wi-Fi, USB or PC needed.

## 8. Day-to-day

```bash
cd ~/CRM/deploy
docker compose logs --tail 100 api     # recent log
docker compose restart api             # restart
docker compose ps                      # status
```

The containers restart by themselves after a reboot (`restart: unless-stopped`).

## 9. Updating the backend

```bash
cd ~/CRM
git pull                        # or re-copy the backend folder (option B)
cd deploy
docker compose up -d --build    # ~1 minute; the app keeps working apart from a few seconds
docker compose logs --tail 50 api
```

To go back after a bad update: `git checkout <previous-commit>` and run the same `docker compose up -d --build`.

## 10. Things to know

- **Secrets:** the Supabase service-role key exists only in `deploy/.env` on the server. It must never go into the app or into Git. If it ever leaks, rotate it in the Supabase dashboard and update `.env`.
- **One worker:** the reminder scheduler runs inside the API, so the API runs as a single process (see `backend/Dockerfile`). Don't raise the worker count.
- **Backups:** the data lives in Supabase, not on the VPS, so the server holds nothing to lose. Use Supabase's own backups for the database.
- **Database changes and the `call-sync` function** are not part of the VPS. They are deployed to Supabase as before (`supabase db push`, `supabase functions deploy call-sync ...`).
- **Not tested here:** Docker was not running on the development PC, so these files have not been built or started yet. Expect to read `docker compose logs` once on the first run.

## Can we add or change features after it is deployed?

Yes. Hosting changes where the backend runs, not what you can build.

| What you change | How it reaches users | Do phones need an update? |
|---|---|---|
| **Backend** (new API, fix, report) | `git pull` + `docker compose up -d --build` on the VPS (~1 min) | **No** — every phone gets it immediately |
| **Database** (new table/column) | New migration, applied to Supabase | **No**, unless the app must show the new data |
| **App screens / behaviour** | Build a new APK and send/install it (or publish through Play Store / Firebase App Distribution) | **Yes** — each phone installs the new APK |

Rules that keep updates safe:

1. **Keep the API backward compatible.** Phones with the old APK keep talking to the new backend. Add new fields and endpoints rather than renaming or removing existing ones, until everyone has updated.
2. **Raise the app version** (`pubspec.yaml` `version:`) with every APK so installs upgrade in place. Always sign with the same key, or phones will refuse the update.
3. **Test the update on the VPS before telling users:** `/health`, then sign in on one phone.
4. Use Firebase App Distribution or the Play Store so updates reach your manager by a link instead of a file; I can set that up.
