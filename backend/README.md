# VoiceApp backend

Node.js Express server that creates **OpenAI Realtime** ephemeral sessions server-side. The iOS app calls `POST /session` and receives the same JSON shape as `https://api.openai.com/v1/realtime/sessions` (including `client_secret`). Your **API key never ships in the app**.

## Prerequisites

- Node.js 18+ (uses native `fetch`)

## Setup

1. Copy environment template and add your key:

   ```bash
   cp .env.example .env
   ```

2. Edit `.env`:

   - `OPENAI_API_KEY` — your OpenAI secret key (server only)
   - `PORT` — default `3000`
   - `NODE_ENV` — `development` for local use

3. Install and run:

   ```bash
   npm install
   npm run start
   ```

   For auto-reload during development:

   ```bash
   npm run dev
   ```

## API

- `GET /health` — `{ "ok": true, "shopify": { ... } }`
- `POST /session` — Proxies to OpenAI Realtime with body:
  - `model`: `gpt-4o-realtime-preview`
  - `voice`: `alloy`
  - `instructions`: `You are a helpful voice assistant.`
  - `modalities`: `["audio","text"]`

Returns OpenAI’s JSON response (status code preserved). The iOS client reads `client_secret.value` (`ek_...`) and must complete WebRTC signaling **within the token lifetime** (about 60 seconds per OpenAI docs).

### Shopify (Groo pedidos y montos)

Configura en `.env`:

- `SHOPIFY_SHOP` — dominio sin protocolo (ej. `drgsmileusa` → `drgsmileusa.myshopify.com`)
- `SHOPIFY_CLIENT_ID` — Client ID de la app en Shopify Partners
- `SHOPIFY_CLIENT_SECRET` — Secret (nunca en la app iOS)
- `SHOPIFY_API_VERSION` — opcional, default `2025-01`

Endpoints:

- `GET /api/shopify/orders?limit=50` — pedidos mapeados para la app
- `GET /api/shopify/summary` — totales y revenue del mes actual

La app iOS llama a estos endpoints vía `SHOPIFY_BACKEND_BASE_URL` (por defecto `http://127.0.0.1:3000` en desarrollo).

### Instagram / Meta webhooks

Configura en `.env` (local) o en **Render → Environment**:

- `INSTAGRAM_APP_ID`
- `INSTAGRAM_APP_SECRET`
- `INSTAGRAM_VERIFY_TOKEN` — mismo valor que pegas en Meta → **Verificar token**
- `INSTAGRAM_WEBHOOK_PUBLIC_BASE_URL` — `https://TU-SERVICIO.onrender.com` (sin slash final)

Endpoints:

- `GET /api/webhooks/instagram` — verificación Meta (`hub.challenge`)
- `POST /api/webhooks/instagram` — eventos

#### Deploy en Render

1. New → **Web Service**
2. Repo Groo, **Root Directory:** `backend`
3. Build: `npm install` · Start: `npm start`
4. Environment (copia de tu `.env` local de Instagram):
   - `INSTAGRAM_APP_ID=1046896744939508`
   - `INSTAGRAM_APP_SECRET=…`
   - `INSTAGRAM_VERIFY_TOKEN=smilestudio_ig_verify_We2rFa7`
   - `INSTAGRAM_WEBHOOK_PUBLIC_BASE_URL=https://TU-SERVICIO.onrender.com`
5. Tras el deploy, en Meta:
   - **URL:** `https://TU-SERVICIO.onrender.com/api/webhooks/instagram`
   - **Verificar token:** `smilestudio_ig_verify_We2rFa7`

Nota: en plan free Render se duerme; abre `/health` una vez antes de verificar en Meta.

## CORS

CORS is enabled with `origin: true` for local development so the simulator or a web test client can reach the server.

## Security

- Do not commit `.env`.
- Do not log full API responses in production if they contain secrets; this sample logs HTTP status and timing only.
