/**
 * Instagram / Meta webhooks:
 * - GET  /api/webhooks/instagram  — verificación (hub.challenge)
 * - POST /api/webhooks/instagram  — eventos de mensajería
 */
import crypto from "crypto";

export function instagramVerifyToken() {
  return (process.env.INSTAGRAM_VERIFY_TOKEN || "").trim();
}

export function instagramAppSecret() {
  return (process.env.INSTAGRAM_APP_SECRET || "").trim();
}

export function instagramAppId() {
  return (process.env.INSTAGRAM_APP_ID || "").trim();
}

export function instagramPublicCallbackUrl() {
  const base = (process.env.INSTAGRAM_WEBHOOK_PUBLIC_BASE_URL || "").trim().replace(/\/$/, "");
  if (!base) return null;
  return `${base}/api/webhooks/instagram`;
}

export function instagramWebhookStatus() {
  return {
    appIdConfigured: Boolean(instagramAppId()),
    secretConfigured: Boolean(instagramAppSecret()),
    verifyTokenConfigured: Boolean(instagramVerifyToken()),
    callbackUrl: instagramPublicCallbackUrl(),
  };
}

/** Meta subscription challenge (GET). */
export function handleInstagramVerify(req, res) {
  const mode = String(req.query["hub.mode"] || "");
  const token = String(req.query["hub.verify_token"] || "");
  const challenge = String(req.query["hub.challenge"] || "");
  const expected = instagramVerifyToken();

  if (!expected) {
    console.warn("[instagram/webhook] INSTAGRAM_VERIFY_TOKEN missing");
    return res.status(500).send("verify_token_not_configured");
  }

  if (mode === "subscribe" && token === expected && challenge) {
    console.info("[instagram/webhook] verified OK");
    return res.status(200).type("text/plain").send(challenge);
  }

  console.warn("[instagram/webhook] verification failed", { mode, tokenMatch: token === expected });
  return res.status(403).send("forbidden");
}

function validSignature(rawBody, signatureHeader, appSecret) {
  if (!signatureHeader || !appSecret) return false;
  const expected =
    "sha256=" +
    crypto.createHmac("sha256", appSecret).update(rawBody).digest("hex");
  try {
    const a = Buffer.from(expected);
    const b = Buffer.from(String(signatureHeader));
    if (a.length !== b.length) return false;
    return crypto.timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

/** Incoming Instagram events (POST). */
export function handleInstagramEvent(req, res) {
  const secret = instagramAppSecret();
  const signature = req.get("x-hub-signature-256");
  const raw = req.rawBody;

  if (secret) {
    if (!raw || !validSignature(raw, signature, secret)) {
      console.warn("[instagram/webhook] invalid signature");
      return res.status(401).json({ error: "invalid_signature" });
    }
  } else {
    console.warn("[instagram/webhook] INSTAGRAM_APP_SECRET missing — accepting without signature check");
  }

  const body = req.body;
  console.info(
    "[instagram/webhook] event",
    JSON.stringify({
      object: body?.object,
      entries: Array.isArray(body?.entry) ? body.entry.length : 0,
    })
  );

  // Acknowledge quickly; process async later (CRM / chat pipeline).
  return res.status(200).json({ ok: true });
}
