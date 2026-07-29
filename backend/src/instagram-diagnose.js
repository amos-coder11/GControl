/**
 * Diagnóstico y suscripción de webhooks para Instagram Messaging.
 *
 * - runInstagramDiagnostics(): sondea Graph y explica por qué no llegan mensajes.
 * - subscribeInstagramWebhooks(): suscribe la app a los eventos de la cuenta IG.
 * - getInstagramSubscriptions(): lista suscripciones activas.
 */
import {
  FB_HOST,
  IG_HOST,
  explainGraphError,
  graphRequest,
  isInstagramLoginToken,
  selfNode,
} from "./instagram-graph.js";
import {
  getInstagramIgUserId,
  getInstagramPageId,
  instagramSendStatus,
} from "./instagram-token.js";
import { instagramWebhookStatus } from "./instagram-webhook.js";

export const WEBHOOK_FIELDS = [
  "messages",
  "messaging_seen",
  "messaging_postbacks",
  "messaging_referral",
  "message_reactions",
];

function summarize(label, res) {
  return {
    check: label,
    ok: res.ok,
    status: res.status,
    error: res.ok ? null : res.error,
    explain: res.ok ? null : explainGraphError(res.error),
    sample: res.ok ? previewJson(res.json) : null,
  };
}

function previewJson(json) {
  if (!json) return null;
  if (Array.isArray(json?.data)) {
    return { count: json.data.length, first: json.data[0] || null };
  }
  return json;
}

/** Suscribe la app a los webhooks de la cuenta Instagram conectada. */
export async function subscribeInstagramWebhooks({ fields = WEBHOOK_FIELDS } = {}) {
  const igLogin = isInstagramLoginToken();
  const node = igLogin ? "me" : getInstagramPageId() || getInstagramIgUserId();
  if (!node) {
    return { ok: false, error: { message: "instagram_target_id_missing" } };
  }

  const res = await graphRequest(`${node}/subscribed_apps`, {
    method: "POST",
    query: { subscribed_fields: fields.join(",") },
    host: igLogin ? IG_HOST : FB_HOST,
  });

  return {
    ok: res.ok,
    status: res.status,
    node,
    fields,
    result: res.json,
    error: res.error,
    explain: res.ok ? null : explainGraphError(res.error),
  };
}

export async function getInstagramSubscriptions() {
  const igLogin = isInstagramLoginToken();
  const node = igLogin ? "me" : getInstagramPageId() || getInstagramIgUserId();
  if (!node) return { ok: false, error: { message: "instagram_target_id_missing" } };

  const res = await graphRequest(`${node}/subscribed_apps`, {
    host: igLogin ? IG_HOST : FB_HOST,
  });
  return {
    ok: res.ok,
    status: res.status,
    node,
    subscriptions: res.json?.data || null,
    error: res.error,
    explain: res.ok ? null : explainGraphError(res.error),
  };
}

/**
 * Batería de sondas contra Graph para saber exactamente qué falla.
 * No expone el token en ningún caso.
 */
export async function runInstagramDiagnostics() {
  const node = selfNode();
  const igLogin = isInstagramLoginToken();
  const host = igLogin ? IG_HOST : FB_HOST;

  const checks = [];

  // 1. ¿El token sirve y a qué cuenta apunta?
  const me = await graphRequest(node, {
    query: { fields: "id,username,name,account_type,profile_picture_url" },
    host,
  });
  checks.push(summarize("token_identity", me));

  // 2. Conversaciones sin campos (la más permisiva)
  const convBare = await graphRequest(`${node}/conversations`, { host });
  checks.push(summarize("conversations_bare", convBare));

  // 3. Conversaciones con participantes
  const convFields = await graphRequest(`${node}/conversations`, {
    query: { fields: "id,updated_time,participants" },
    host,
  });
  checks.push(summarize("conversations_with_participants", convFields));

  // 4. Variante Messenger Platform (platform=instagram) — la que usaba el sync viejo
  const convPlatform = await graphRequest(`${node}/conversations`, {
    query: { platform: "instagram", fields: "id,updated_time" },
    host,
  });
  checks.push(summarize("conversations_platform_param", convPlatform));

  // 4b. Forma cruda de un mensaje con adjunto: sin esto hay que adivinar cómo
  // viene el audio, y Meta usa varios formatos según el tipo de mensaje.
  const firstConvId = convFields.json?.data?.[0]?.id;
  if (firstConvId) {
    const msgs = await graphRequest(firstConvId, {
      query: {
        fields: "messages.limit(5){id,created_time,from,message,attachments}",
      },
      host,
    });
    checks.push({
      check: "message_shape_sample",
      ok: msgs.ok,
      status: msgs.status,
      error: msgs.ok ? null : msgs.error,
      explain: msgs.ok ? null : explainGraphError(msgs.error),
      sample: msgs.ok ? msgs.json?.messages?.data?.slice(0, 3) || null : null,
    });

    // La expansión anidada omite los adjuntos; el nodo individual sí los trae.
    const firstMsgId = msgs.json?.messages?.data?.[0]?.id;
    if (firstMsgId) {
      for (const fields of [
        "id,created_time,from,message,attachments",
        "id,created_time,from,message,shares,story",
        "id,message,attachments{id,name,mime_type,size,file_url,image_data,video_data,audio_data}",
      ]) {
        const one = await graphRequest(firstMsgId, { query: { fields }, host });
        checks.push({
          check: `single_message[${fields.split(",").pop()}]`,
          ok: one.ok,
          status: one.status,
          error: one.ok ? null : one.error,
          sample: one.ok ? one.json : null,
        });
      }
    }
  }

  // 5. Suscripción a webhooks
  const subs = await graphRequest(`${igLogin ? "me" : getInstagramPageId() || node}/subscribed_apps`, {
    host,
  });
  checks.push(summarize("webhook_subscriptions", subs));

  const failing = checks.filter((c) => !c.ok);
  const blocked = failing.find((c) => c.explain?.cause === "instagram_message_access_off");
  const subsCheck = checks.find((c) => c.check === "webhook_subscriptions");
  const subscribedFields =
    subsCheck?.sample?.first?.subscribed_fields ||
    subsCheck?.sample?.subscribed_fields ||
    null;

  const blockers = [];
  if (blocked) blockers.push(blocked.explain.hint);
  if (subsCheck?.ok && !subscribedFields) {
    blockers.push(
      "La app no está suscrita a los webhooks de la cuenta. Llama POST /api/instagram/subscribe."
    );
  }
  if (!instagramWebhookStatus().callbackUrl) {
    blockers.push("Falta INSTAGRAM_WEBHOOK_PUBLIC_BASE_URL en el entorno de Render.");
  }

  return {
    tokenKind: igLogin ? "instagram_login (IGAA)" : "page_or_other",
    node,
    host,
    status: { ...instagramWebhookStatus(), ...redactStatus(instagramSendStatus()) },
    checks,
    subscribedFields,
    blockers,
    verdict: blockers.length === 0 && failing.length === 0 ? "ready" : "needs_action",
  };
}

function redactStatus(status) {
  const copy = { ...status };
  delete copy.tokenPreview;
  return copy;
}
