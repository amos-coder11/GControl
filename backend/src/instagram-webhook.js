/**
 * Instagram / Meta webhooks:
 * - GET  /api/webhooks/instagram  — verificación (hub.challenge)
 * - POST /api/webhooks/instagram  — eventos de mensajería
 */
import crypto from "crypto";
import { ingestInstagramWebhook } from "./instagram-store.js";
import { notifyInstagramIncomingMessage } from "./crm-push.js";
import { maybeAutoReplyCrmMessage } from "./crm-ai.js";
import {
  enrichConversationProfile,
  rememberWebhookEvent,
} from "./instagram-sync.js";

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

export async function sendInstagramText({ igsid, text }) {
  const {
    getInstagramPageAccessToken,
    getInstagramPageId,
    getInstagramIgUserId,
  } = await import("./instagram-token.js");

  const accessToken = getInstagramPageAccessToken();
  if (!accessToken) {
    const err = new Error("instagram_page_token_missing");
    err.code = "instagram_page_token_missing";
    throw err;
  }

  const isIgUserToken = accessToken.startsWith("IGAA");
  const igUserId = getInstagramIgUserId();
  const pageId = getInstagramPageId();

  /** @type {{ url: string, headers: Record<string, string>, body: string }[]} */
  const attempts = [];

  const payload = JSON.stringify({
    recipient: { id: igsid },
    message: { text },
  });
  const payloadWithType = JSON.stringify({
    recipient: { id: igsid },
    messaging_type: "RESPONSE",
    message: { text },
  });

  if (isIgUserToken || igUserId) {
    let resolvedIgUserId = igUserId;
    if (!resolvedIgUserId || isIgUserToken) {
      try {
        const { resolveInstagramBusinessId } = await import("./instagram-sync.js");
        resolvedIgUserId = (await resolveInstagramBusinessId()) || igUserId;
      } catch {
        // keep configured id
      }
    }
    if (!resolvedIgUserId) {
      const err = new Error("instagram_ig_user_id_missing");
      err.code = "instagram_ig_user_id_missing";
      throw err;
    }
    // Instagram API with Instagram Login
    attempts.push({
      url: `https://graph.instagram.com/v21.0/${resolvedIgUserId}/messages`,
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: payload,
    });
    attempts.push({
      url: `https://graph.facebook.com/v21.0/${resolvedIgUserId}/messages?access_token=${encodeURIComponent(accessToken)}`,
      headers: { "Content-Type": "application/json" },
      body: payload,
    });
  }

  // Messenger Platform (Page Access Token)
  const messengerPath = pageId ? `${pageId}/messages` : "me/messages";
  attempts.push({
    url: `https://graph.facebook.com/v21.0/${messengerPath}?access_token=${encodeURIComponent(accessToken)}`,
    headers: { "Content-Type": "application/json" },
    body: payloadWithType,
  });

  let lastError = null;
  for (const attempt of attempts) {
    try {
      const upstream = await fetch(attempt.url, {
        method: "POST",
        headers: attempt.headers,
        body: attempt.body,
      });
      const bodyText = await upstream.text();
      let json = null;
      try {
        json = bodyText ? JSON.parse(bodyText) : null;
      } catch {
        json = { raw: bodyText.slice(0, 400) };
      }
      if (upstream.ok) return json;
      lastError = {
        status: upstream.status,
        details: json,
        message: json?.error?.message || `instagram_send_failed_${upstream.status}`,
      };
      console.warn("[instagram/send] attempt failed", lastError.message);
    } catch (err) {
      lastError = {
        status: 0,
        details: null,
        message: String(err?.message || err),
      };
    }
  }

  const err = new Error(lastError?.message || "instagram_send_failed");
  err.code = "instagram_send_failed";
  err.status = lastError?.status || 502;
  err.details = lastError?.details || null;
  throw err;
}

export async function sendInstagramImage({ igsid, imageUrl }) {
  return sendInstagramAttachment({ igsid, mediaUrl: imageUrl, type: "image" });
}

/** Nota de voz saliente. Meta la entrega como audio reproducible en el DM. */
export async function sendInstagramAudio({ igsid, audioUrl }) {
  return sendInstagramAttachment({ igsid, mediaUrl: audioUrl, type: "audio" });
}

/**
 * Envía un adjunto por URL pública. Meta descarga el fichero desde nuestro
 * servidor, así que la URL debe ser accesible sin autenticación.
 */
export async function sendInstagramAttachment({ igsid, mediaUrl, type = "image" }) {
  const {
    getInstagramPageAccessToken,
    getInstagramPageId,
    getInstagramIgUserId,
  } = await import("./instagram-token.js");

  const accessToken = getInstagramPageAccessToken();
  if (!accessToken) {
    const err = new Error("instagram_page_token_missing");
    err.code = "instagram_page_token_missing";
    throw err;
  }

  const url = String(mediaUrl || "").trim();
  if (!url) {
    const err = new Error("media_url_required");
    err.code = "media_url_required";
    throw err;
  }

  const isIgUserToken = accessToken.startsWith("IGAA");
  const igUserId = getInstagramIgUserId();
  const pageId = getInstagramPageId();

  const attachmentPayload = JSON.stringify({
    recipient: { id: igsid },
    message: {
      attachment: {
        type,
        payload: { url, is_reusable: true },
      },
    },
  });
  const attachmentPayloadWithType = JSON.stringify({
    recipient: { id: igsid },
    messaging_type: "RESPONSE",
    message: {
      attachment: {
        type,
        payload: { url, is_reusable: true },
      },
    },
  });

  /** @type {{ url: string, headers: Record<string, string>, body: string }[]} */
  const attempts = [];

  if (isIgUserToken || igUserId) {
    let resolvedIgUserId = igUserId;
    if (!resolvedIgUserId || isIgUserToken) {
      try {
        const { resolveInstagramBusinessId } = await import("./instagram-sync.js");
        resolvedIgUserId = (await resolveInstagramBusinessId()) || igUserId;
      } catch {
        // keep configured id
      }
    }
    if (!resolvedIgUserId) {
      const err = new Error("instagram_ig_user_id_missing");
      err.code = "instagram_ig_user_id_missing";
      throw err;
    }
    attempts.push({
      url: `https://graph.instagram.com/v21.0/${resolvedIgUserId}/messages`,
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: attachmentPayload,
    });
    attempts.push({
      url: `https://graph.facebook.com/v21.0/${resolvedIgUserId}/messages?access_token=${encodeURIComponent(accessToken)}`,
      headers: { "Content-Type": "application/json" },
      body: attachmentPayload,
    });
  }

  const messengerPath = pageId ? `${pageId}/messages` : "me/messages";
  attempts.push({
    url: `https://graph.facebook.com/v21.0/${messengerPath}?access_token=${encodeURIComponent(accessToken)}`,
    headers: { "Content-Type": "application/json" },
    body: attachmentPayloadWithType,
  });

  let lastError = null;
  for (const attempt of attempts) {
    try {
      const upstream = await fetch(attempt.url, {
        method: "POST",
        headers: attempt.headers,
        body: attempt.body,
      });
      const bodyText = await upstream.text();
      let json = null;
      try {
        json = bodyText ? JSON.parse(bodyText) : null;
      } catch {
        json = { raw: bodyText.slice(0, 400) };
      }
      if (upstream.ok) return json;
      lastError = {
        status: upstream.status,
        details: json,
        message: json?.error?.message || `instagram_send_failed_${upstream.status}`,
      };
      console.warn(`[instagram/send-${type}] attempt failed`, lastError.message);
    } catch (err) {
      lastError = {
        status: 0,
        details: null,
        message: String(err?.message || err),
      };
    }
  }

  const err = new Error(lastError?.message || "instagram_send_failed");
  err.code = "instagram_send_failed";
  err.status = lastError?.status || 502;
  err.details = lastError?.details || null;
  throw err;
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
      rememberWebhookEvent({
        ok: false,
        reason: "invalid_signature",
        object: req.body?.object,
      });
      return res.status(401).json({ error: "invalid_signature" });
    }
  } else {
    console.warn("[instagram/webhook] INSTAGRAM_APP_SECRET missing — accepting without signature check");
  }

  const body = req.body;
  let stored = 0;
  let customerIds = [];
  /** @type {Array<{ conversationId: string, text: string, contactName: string | null }>} */
  let incomingMessages = [];
  try {
    const result = ingestInstagramWebhook(body);
    stored = result?.added || 0;
    customerIds = result?.customerIds || [];
    incomingMessages = result?.incoming || [];
  } catch (err) {
    console.error("[instagram/webhook] ingest failed:", err?.message || err);
  }

  rememberWebhookEvent({
    ok: true,
    object: body?.object,
    entries: Array.isArray(body?.entry) ? body.entry.length : 0,
    stored,
    customerIds,
  });

  console.info(
    "[instagram/webhook] event",
    JSON.stringify({
      object: body?.object,
      entries: Array.isArray(body?.entry) ? body.entry.length : 0,
      stored,
    })
  );

  // Enrich name + profile photo asynchronously (don't block Meta ACK).
  if (customerIds.length > 0) {
    Promise.allSettled(
      customerIds.map((id) => enrichConversationProfile(`ig:${id}`, id))
    ).catch(() => {});
  }

  // Push APNs + respuesta automática IA (Zelle / pagos).
  if (incomingMessages.length > 0) {
    Promise.allSettled(
      incomingMessages.map(async (msg) => {
        const aiResult = await maybeAutoReplyCrmMessage(msg);
        if (aiResult.ok) {
          console.info("[instagram/webhook] crm-ai replied", msg.conversationId);
        }
        const result = await notifyInstagramIncomingMessage(msg);
        if (!result.ok) {
          console.warn("[instagram/webhook] crm push failed", msg.conversationId, result);
        }
      })
    ).catch(() => {});
  }

  return res.status(200).json({ ok: true, stored });
}
