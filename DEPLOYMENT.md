# Karada — Deployment Guide

## Architecture
```
Flutter (Web + Android)
        ↓  REST + WebSocket
Go Incident API  ←→  Python Hotline Service
                          ↓
                  Notification Worker
```

---

## Step 1 — Deploy the Go Incident API

### Option A: Render.com (recommended, free tier)
1. Push this repo to GitHub
2. Go to [render.com](https://render.com) → **New** → **Blueprint**
3. Connect your repo — Render will detect `render.yaml` automatically
4. Click **Apply** — the `karada-incident-api` service will deploy
5. Copy the URL: `https://karada-incident-api.onrender.com`

### Option B: Railway.app
1. Install CLI: `npm i -g @railway/cli`
2. `railway login`
3. `railway init` (from repo root)
4. `railway up`
5. `railway domain` — copy the generated URL

### Option C: Fly.io
```bash
cd backend/incident-service
fly launch --name karada-incident-api
fly deploy
fly status  # get the URL
```

---

## Step 2 — Deploy the Python Hotline Service

### Render.com
Already included in `render.yaml` as `karada-hotline`.
It auto-links to the Go API via `API_GATEWAY_URL`.

### Manual (Railway/Fly)
```bash
# Set env var pointing to your deployed Go API
API_GATEWAY_URL=https://karada-incident-api.onrender.com

# Railway
railway variables set API_GATEWAY_URL=$API_GATEWAY_URL

# Or Fly
fly secrets set API_GATEWAY_URL=$API_GATEWAY_URL
```

---

## Step 3 — Connect Flutter to the Deployed API

Once you have the Go API URL (e.g. `https://karada-incident-api.onrender.com`),
build the Flutter app with it injected:

### Android APK
```bash
cd firefix_mobile
flutter build apk --dart-define=BASE_URL=https://karada-incident-api.onrender.com
# Output: build/app/outputs/flutter-apk/app-release.apk
```

### Web
```bash
flutter build web --dart-define=BASE_URL=https://karada-incident-api.onrender.com
# Output: build/web/  → deploy to Netlify, Vercel, or Firebase Hosting
```

### Local dev (Android emulator)
No extra flags needed — `10.0.2.2:8090` maps to your host machine's localhost.

### Local dev (physical device)
```bash
flutter run --dart-define=BASE_URL=http://<YOUR_LOCAL_IP>:8090
```

---

## Step 4 — Deploy Flutter Web (optional)

### Netlify (drag & drop)
1. `flutter build web --dart-define=BASE_URL=https://karada-incident-api.onrender.com`
2. Drag the `build/web` folder to [netlify.com/drop](https://app.netlify.com/drop)

### Vercel
```bash
npm i -g vercel
flutter build web --dart-define=BASE_URL=https://...
cd build/web
vercel deploy
```

---

## Environment Variables Summary

| Service | Variable | Value |
|---|---|---|
| Go Incident API | `PORT` | `8090` |
| Python Hotline | `API_GATEWAY_URL` | Go API base URL |
| Flutter build | `BASE_URL` | Go API base URL |
| Flutter build | `MAP_BACKEND_BASE_URL` | Map backend URL |

---

## Testing the connection

```bash
# Check Go API is up
curl https://karada-incident-api.onrender.com/health

# Submit a test incident
curl -X POST https://karada-incident-api.onrender.com/api/incidents \
  -H "Content-Type: application/json" \
  -d '{"type":"fire","description":"Test fire","latitude":-1.2921,"longitude":36.8219,"severity":"high"}'

# List all incidents
curl https://karada-incident-api.onrender.com/api/incidents
```
