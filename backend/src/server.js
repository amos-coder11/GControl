/**
 * Express server:
 * - POST /session — OpenAI Realtime (clave solo en servidor)
 * - GET /api/shopify/orders — pedidos Shopify para Gflow iOS
 * - GET /api/shopify/summary — totales y revenue del mes
 */
import cors from "cors";
import dotenv from "dotenv";
import express from "express";
import {
  handleInstagramEvent,
  handleInstagramVerify,
  instagramWebhookStatus,
  sendInstagramText,
} from "./instagram-webhook.js";
import {
  getInstagramPageAccessToken,
  instagramSendStatus,
  saveInstagramPageToken,
} from "./instagram-token.js";
import {
  appendOutgoing,
  getConversation,
  listConversations,
  listMessages,
  setAiActive,
  setAllAiActive,
} from "./instagram-store.js";
import {
  enrichConversationProfile,
  getRecentWebhookEvents,
  syncInstagramInboxFromGraph,
} from "./instagram-sync.js";
import {
  buildInstagramBusinessLoginUrl,
  handleInstagramOAuthCallback,
  instagramOAuthRedirectUri,
} from "./instagram-oauth.js";
import {
  buildInstallUrl,
  handleInstallCallback,
  installStatus,
  saveManualAccessToken,
} from "./shopify-auth.js";
import {
  fetchShopifyOrders,
  fetchShopifySummary,
  shopifyHealth,
} from "./shopify.js";

dotenv.config();

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const PORT = Number(process.env.PORT) || 3000;
const NODE_ENV = process.env.NODE_ENV || "development";

const OPENAI_SESSIONS_URL = "https://api.openai.com/v1/realtime/sessions";

const SESSION_BODY = {
  model: "gpt-4o-realtime-preview",
  voice: "alloy",
  instructions: "You are a helpful voice assistant.",
  modalities: ["audio", "text"],
};

function logRequest(req, res, start, status) {
  const ts = new Date().toISOString();
  console.info(
    `[${ts}] ${req.method} ${req.path} -> ${status} (${Date.now() - start}ms)`
  );
}

const app = express();

// Preserve raw body for Meta X-Hub-Signature-256 on Instagram webhook.
app.use(
  express.json({
    limit: "2mb",
    verify: (req, _res, buf) => {
      if (req.originalUrl?.startsWith("/api/webhooks/instagram")) {
        req.rawBody = buf;
      }
    },
  })
);

app.use(
  cors({
    origin: true,
    methods: ["GET", "POST", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Accept", "Authorization"],
  })
);

app.get("/health", (req, res) => {
  const ig = {
    ...instagramWebhookStatus(),
    ...instagramSendStatus(),
  };
  // Never expose token fragments on a public health endpoint.
  delete ig.tokenPreview;
  res.status(200).json({
    ok: true,
    shopify: shopifyHealth(),
    install: installStatus(),
    instagram: ig,
  });
});

// Instagram / Meta webhooks (callback URL + verify token)
app.get("/api/webhooks/instagram", handleInstagramVerify);
app.post("/api/webhooks/instagram", handleInstagramEvent);

// Pegar token Instagram para poder responder DMs desde la app
app.get("/api/instagram/connect", (req, res) => {
  const status = instagramSendStatus();
  const webhook = instagramWebhookStatus();
  res.status(200).send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8"><title>Groo · Instagram Messaging</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body{font-family:-apple-system,sans-serif;max-width:640px;margin:40px auto;padding:0 20px;color:#111;line-height:1.45}
h1{font-size:24px}.ok{color:#0a7a3e}.warn{color:#b45309}
code{background:#f3f4f6;padding:2px 6px;border-radius:6px;word-break:break-all}
input,textarea{width:100%;padding:10px;border:1px solid #d1d5db;border-radius:8px;margin:8px 0;box-sizing:border-box}
button{padding:10px 16px;border:0;border-radius:8px;background:#111827;color:#fff;font-weight:600}
ol{padding-left:20px}li{margin:8px 0}
</style></head><body>
<h1>Conectar respuestas Instagram</h1>
<p>Estado envío: <strong class="${status.pageTokenConfigured ? "ok" : "warn"}">${status.pageTokenConfigured ? "Listo para responder" : "Falta access token"}</strong></p>
${status.username ? `<p>Cuenta: <strong>@${status.username}</strong></p>` : ""}
${status.tokenPreview ? `<p>Token: <code>${status.tokenPreview}</code> (${status.tokenKind || "—"})</p>` : ""}
${status.igUserIdConfigured ? `<p>IG User ID configurado ✅</p>` : `<p class="warn">Falta IG User ID</p>`}
<p>Webhook: <code>${webhook.callbackUrl || "—"}</code></p>
<form method="POST" action="/api/instagram/token">
  <label>Username (opcional)</label>
  <input name="username" placeholder="smilestudiowellness" value="${status.username || ""}">
  <label>IG User ID</label>
  <input name="igUserId" placeholder="17841400024368275" required>
  <label>Access Token (IGAA… o EAAB…)</label>
  <textarea name="token" rows="4" placeholder="IGAA... o 1784...=IGAA..." required></textarea>
  <label>Page ID (opcional, solo si usas token de Facebook Page)</label>
  <input name="pageId" placeholder="1234567890">
  <button type="submit">Guardar y activar respuestas</button>
</form>
<p class="warn">Sin token + IG User ID, los DMs llegan a la app pero no se pueden enviar respuestas.</p>
</body></html>`);
});

app.post("/api/instagram/token", express.urlencoded({ extended: false }), (req, res) => {
  try {
    const saved = saveInstagramPageToken({
      accessToken: req.body?.token,
      pageId: req.body?.pageId,
      igUserId: req.body?.igUserId,
      username: req.body?.username,
    });
    return res.redirect(
      `/api/instagram/connect?ok=1&preview=${encodeURIComponent(saved.tokenPreview)}`
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "token_error";
    return res.status(400).send(`<p>Error: ${message}</p><p><a href="/api/instagram/connect">Volver</a></p>`);
  }
});

// Instagram Business Login — Redirect URL for Meta dashboard
app.get("/api/instagram/oauth/callback", async (req, res) => {
  try {
    const result = await handleInstagramOAuthCallback({
      code: req.query.code,
      error: req.query.error,
      errorReason: req.query.error_reason || req.query.error_description,
    });
    if (!result.ok) {
      return res.status(400).send(`<!DOCTYPE html><html><body style="font-family:-apple-system;padding:40px">
<h1>Login Instagram falló</h1><p>${result.message}</p>
<p><a href="/api/instagram/connect">Volver</a></p></body></html>`);
    }
    return res.status(200).send(`<!DOCTYPE html><html><body style="font-family:-apple-system;padding:40px;max-width:640px;margin:auto">
<h1 style="color:#0a7a3e">✅ Instagram conectado</h1>
<p>Cuenta: <strong>@${result.username || "—"}</strong></p>
<p>IG User ID: <code>${result.igUserId || "—"}</code></p>
<p>Token: <code>${result.tokenPreview || "—"}</code></p>
${result.expiresIn ? `<p>Expira en ~${Math.round(Number(result.expiresIn) / 86400)} días</p>` : ""}
<p>Ya puedes cerrar esta ventana y abrir Groo → Chat → Instagram.</p>
<p><a href="/api/instagram/connect">Ver estado</a></p>
</body></html>`);
  } catch (err) {
    console.error("[instagram/oauth]", err?.message || err);
    return res.status(500).send(`<!DOCTYPE html><html><body style="font-family:-apple-system;padding:40px">
<h1>Error OAuth</h1><pre>${String(err?.message || err)}</pre>
<p>Redirect URI configurada: <code>${instagramOAuthRedirectUri()}</code></p>
</body></html>`);
  }
});

app.get("/api/instagram/login", (req, res) => {
  try {
    const url = buildInstagramBusinessLoginUrl();
    return res.redirect(url);
  } catch (err) {
    return res.status(500).json({
      error: "instagram_login_misconfigured",
      message: err?.message || "login_error",
      redirectUri: instagramOAuthRedirectUri(),
    });
  }
});

app.get("/api/instagram/oauth/redirect-uri", (req, res) => {
  res.status(200).json({
    redirectUri: instagramOAuthRedirectUri(),
    pasteInMeta: instagramOAuthRedirectUri(),
    note: "Meta → Instagram → API setup → Set up Instagram business login → Redirect URL",
  });
});

// Meta Business login settings — Deauthorize callback
app.all("/api/instagram/deauthorize", express.urlencoded({ extended: false }), (req, res) => {
  const signed =
    req.body?.signed_request ||
    req.query?.signed_request ||
    null;
  console.info("[instagram/deauthorize]", {
    method: req.method,
    hasSignedRequest: Boolean(signed),
  });
  // ACK quickly; token cleanup can be expanded later.
  return res.status(200).json({ ok: true });
});

// Meta Business login settings — Data deletion request callback
app.all("/api/instagram/data-deletion", express.urlencoded({ extended: false }), (req, res) => {
  const signed =
    req.body?.signed_request ||
    req.query?.signed_request ||
    null;
  const confirmationCode = `groo-ig-del-${Date.now()}`;
  const statusUrl = `https://smilestudio-backend.onrender.com/api/instagram/data-deletion/status?code=${encodeURIComponent(confirmationCode)}`;
  console.info("[instagram/data-deletion]", {
    method: req.method,
    hasSignedRequest: Boolean(signed),
    confirmationCode,
  });
  // Meta expects JSON with url + confirmation_code
  return res.status(200).json({
    url: statusUrl,
    confirmation_code: confirmationCode,
  });
});

app.get("/api/instagram/data-deletion/status", (req, res) => {
  const code = String(req.query.code || "");
  res.status(200).send(`<!DOCTYPE html><html><body style="font-family:-apple-system;padding:40px;max-width:640px;margin:auto">
<h1>Solicitud de borrado</h1>
<p>Código: <code>${code || "—"}</code></p>
<p>Estado: <strong style="color:#0a7a3e">Recibida / procesada</strong></p>
<p>Smile Studio Wellness · Groo</p>
</body></html>`);
});

// CRM-compatible inbox APIs (consumed by iOS CrmChatService)
app.get("/api/whatsapp/get_conversations", async (req, res) => {
  const limit = Number(req.query.limit) || 100;
  // Pull from Graph when local store is empty / stale so the app sees real DMs.
  try {
    await syncInstagramInboxFromGraph({ limit });
  } catch (err) {
    console.warn("[instagram/sync]", err?.message || err);
  }
  const data = listConversations(limit);
  return res.status(200).json({ data, conversations: data });
});

app.post("/api/instagram/sync", async (req, res) => {
  try {
    const result = await syncInstagramInboxFromGraph({
      limit: Number(req.body?.limit) || 25,
    });
    return res.status(200).json({ ok: true, ...result });
  } catch (err) {
    return res.status(502).json({
      error: "instagram_sync_failed",
      message: err?.message || "sync_failed",
    });
  }
});

app.get("/api/instagram/debug", (req, res) => {
  res.status(200).json({
    health: {
      ...instagramWebhookStatus(),
      ...instagramSendStatus(),
    },
    conversations: listConversations(20),
    recentWebhooks: getRecentWebhookEvents(),
  });
});

app.get("/api/whatsapp/get_messages", (req, res) => {
  const conversationId = String(req.query.conversationId || "");
  if (!conversationId) {
    return res.status(400).json({ error: "conversationId_required" });
  }
  const limit = Number(req.query.limit) || 100;
  return res.status(200).json({ data: listMessages(conversationId, limit) });
});

function sendContactPhoto(req, res) {
  const conversationId = String(req.query.conversationId || "");
  const wa = String(req.query.wa_user_id || "");
  const convId = conversationId || wa;
  if (!convId) {
    return res.status(400).json({ error: "conversationId_required" });
  }
  const igsid = convId.startsWith("ig:") ? convId.slice(3) : convId;
  const fullId = convId.startsWith("ig:") ? convId : `ig:${igsid}`;

  return (async () => {
    let conv = getConversation(fullId);
    if (!conv?.contact_photo_url) {
      await enrichConversationProfile(fullId, igsid);
      conv = getConversation(fullId);
    }
    return res.status(200).json({
      url: conv?.contact_photo_url || null,
      contact_photo_url: conv?.contact_photo_url || null,
      contact_name: conv?.contact_name || null,
    });
  })().catch((err) => {
    console.warn("[instagram/photo]", err?.message || err);
    return res.status(200).json({ url: null, contact_photo_url: null });
  });
}

app.get("/api/whatsapp/get_contact_profile_picture", sendContactPhoto);
app.get("/api/whatsapp/get_profile_picture", sendContactPhoto);
app.get("/api/whatsapp/get_contact_photo", sendContactPhoto);

app.post("/api/whatsapp/ai_toggle", (req, res) => {
  const conversationId = String(req.body?.conversationId || "");
  const active = Boolean(req.body?.active);
  if (!conversationId) {
    return res.status(400).json({ error: "conversationId_required" });
  }
  setAiActive(conversationId, active);
  return res.status(200).json({ ok: true, conversationId, active });
});

app.post("/api/whatsapp/ai_toggle_all", (req, res) => {
  const active = Boolean(req.body?.active);
  setAllAiActive(active);
  return res.status(200).json({ ok: true, active });
});

app.post("/api/whatsapp/send_message", async (req, res) => {
  const conversationId = String(req.body?.conversationId || "");
  const text = String(req.body?.textContent || req.body?.text || "").trim();
  if (!conversationId || !text) {
    return res.status(400).json({ error: "conversationId_and_text_required" });
  }

  const igsid = conversationId.startsWith("ig:")
    ? conversationId.slice(3)
    : null;
  if (!igsid) {
    return res.status(400).json({ error: "instagram_conversation_required" });
  }

  if (!getInstagramPageAccessToken()) {
    return res.status(503).json({
      error: "instagram_page_token_missing",
      message:
        "Falta Page Access Token. Ábrelo en /api/instagram/connect y pégalo.",
      setupUrl: "/api/instagram/connect",
    });
  }

  try {
    const graph = await sendInstagramText({ igsid, text });
    appendOutgoing(conversationId, text);
    return res.status(200).json({ ok: true, conversationId, graph });
  } catch (err) {
    console.warn("[instagram/send]", err?.message || err, err?.details || "");
    return res.status(502).json({
      error: err?.code || "instagram_send_failed",
      message: err?.message || "instagram_send_failed",
      details: err?.details || null,
    });
  }
});

app.get("/api/shopify/install", (req, res) => {
  try {
    const { preferredInstallUrl, redirectUri, scopes } = buildInstallUrl();
    console.info("[shopify/install] redirect_uri:", redirectUri, "scopes:", scopes);
    return res.redirect(preferredInstallUrl);
  } catch (err) {
    const message = err instanceof Error ? err.message : "shopify_install_error";
    return res.status(500).json({ error: message });
  }
});

app.get("/api/shopify/connect", (req, res) => {
  const status = installStatus();
  const health = shopifyHealth();
  res.status(200).send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8"><title>Gflow · Conectar Shopify</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body{font-family:-apple-system,sans-serif;max-width:640px;margin:40px auto;padding:0 20px;color:#111}
h1{font-size:24px}.ok{color:#0a7a3e}.warn{color:#b45309}
.btn{display:inline-block;margin:12px 0;padding:12px 18px;background:#2563eb;color:#fff;text-decoration:none;border-radius:10px;font-weight:600}
code{background:#f3f4f6;padding:2px 6px;border-radius:6px}
input{width:100%;padding:10px;border:1px solid #d1d5db;border-radius:8px;margin:8px 0}
button{padding:10px 16px;border:0;border-radius:8px;background:#111827;color:#fff;font-weight:600}
</style></head><body>
<h1>Conectar Shopify → Gflow</h1>
<p>Tienda: <strong>${status.shop || "—"}</strong></p>
<p>Estado: <strong class="${health.installed ? "ok" : "warn"}">${health.installed ? "Conectado" : "Pendiente"}</strong></p>
${health.installed ? `<p class="ok">✅ Ya conectado. Abre Gflow y recarga Pedidos.</p>` : `
<p>1. Pulsa instalar y aprueba en Shopify Admin:</p>
<a class="btn" href="/api/shopify/install">Instalar app en drgsmileusa</a>
<p>2. Si Shopify pide redirect URI, añade en Partners:</p>
<p><code>${status.redirectUri}</code></p>
<hr>
<p><strong>O</strong> pega un Admin API token (<code>shpat_...</code>) de Settings → Apps → Develop apps:</p>
<form method="POST" action="/api/shopify/token">
  <input name="token" placeholder="shpat_..." required>
  <button type="submit">Conectar con token</button>
</form>`}
</body></html>`);
});

app.post("/api/shopify/token", express.urlencoded({ extended: false }), (req, res) => {
  try {
    const session = saveManualAccessToken(req.body?.token);
    return res.redirect(`/api/shopify/connect?ok=1&shop=${encodeURIComponent(session.shop || "")}`);
  } catch (err) {
    const message = err instanceof Error ? err.message : "shopify_token_error";
    return res.status(400).send(`<p>Error: ${message}</p><p><a href="/api/shopify/connect">Volver</a></p>`);
  }
});

app.get("/api/shopify/install-url", (req, res) => {
  try {
    const urls = buildInstallUrl();
    return res.status(200).json({
      ...urls,
      installPath: "/api/shopify/install",
      note: "Abre /api/shopify/install en el navegador e inicia sesión en drgsmileusa.",
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "shopify_install_error";
    return res.status(500).json({ error: message });
  }
});

app.get("/api/shopify/callback", async (req, res) => {
  try {
    const session = await handleInstallCallback(req.query);
    return res.status(200).send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8"><title>Gflow · Shopify instalado</title>
<style>body{font-family:-apple-system,sans-serif;max-width:560px;margin:48px auto;padding:0 20px;color:#111}
.ok{color:#0a7a3e;font-size:22px;font-weight:700}p{line-height:1.5}</style></head>
<body><p class="ok">✅ App instalada en ${session.shop}</p>
<p>Token guardado. Ya puedes cerrar esta ventana y volver a Gflow.</p>
<p>Scopes: ${session.scope}</p></body></html>`);
  } catch (err) {
    const message = err instanceof Error ? err.message : "shopify_install_error";
    console.error("[shopify/callback]", message);
    return res.status(400).send(`<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8"><title>Error instalación</title></head>
<body><h1>No se pudo instalar</h1><pre>${message}</pre>
<p>Verifica en Shopify Partners que el redirect URI sea:<br><code>${process.env.SHOPIFY_REDIRECT_URI || `http://127.0.0.1:${PORT}/api/shopify/callback`}</code></p></body></html>`);
  }
});

app.get("/api/shopify/status", (req, res) => {
  res.status(200).json({
    health: shopifyHealth(),
    install: installStatus(),
  });
});

app.get("/api/shopify/orders", async (req, res) => {
  const start = Date.now();
  const limit = Number(req.query.limit) || 50;
  try {
    const payload = await fetchShopifyOrders({ limit });
    logRequest(req, res, start, 200);
    return res.status(200).json(payload);
  } catch (err) {
    const message = err instanceof Error ? err.message : "shopify_error";
    console.error("[shopify/orders]", message);
    logRequest(req, res, start, 502);
    return res.status(502).json({ error: "shopify_fetch_failed", message });
  }
});

app.get("/api/shopify/summary", async (req, res) => {
  const start = Date.now();
  try {
    const payload = await fetchShopifySummary();
    logRequest(req, res, start, 200);
    return res.status(200).json(payload);
  } catch (err) {
    const message = err instanceof Error ? err.message : "shopify_error";
    console.error("[shopify/summary]", message);
    logRequest(req, res, start, 502);
    return res.status(502).json({ error: "shopify_fetch_failed", message });
  }
});

app.post("/session", async (req, res) => {
  const start = Date.now();

  if (!OPENAI_API_KEY || OPENAI_API_KEY.trim() === "") {
    logRequest(req, res, start, 500);
    return res.status(500).json({
      error: "server_misconfigured",
      message: "OPENAI_API_KEY is not set on the server.",
    });
  }

  try {
    const upstream = await fetch(OPENAI_SESSIONS_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(SESSION_BODY),
    });

    const text = await upstream.text();
    let json;
    try {
      json = text ? JSON.parse(text) : {};
    } catch {
      logRequest(req, res, start, upstream.status);
      return res.status(502).json({
        error: "upstream_invalid_json",
        message: "OpenAI returned non-JSON body.",
      });
    }

    logRequest(req, res, start, upstream.status);
    return res.status(upstream.status).json(json);
  } catch (err) {
    logRequest(req, res, start, 502);
    console.error("[session] fetch error:", err);
    return res.status(502).json({
      error: "upstream_unreachable",
      message: "Could not reach OpenAI API.",
    });
  }
});

app.listen(PORT, () => {
  console.info(
    `[voiceapp-backend] listening on :${PORT} (NODE_ENV=${NODE_ENV})`
  );
});
