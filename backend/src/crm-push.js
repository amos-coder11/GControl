/**
 * Avisos APNs vía Supabase Edge Function `send-message-push` cuando llega un DM de Instagram.
 */
import crypto from "crypto";
import { getConversation } from "./instagram-store.js";

const DEFAULT_PUSH_URL =
  "https://fwdfhbgcurimqufbwkux.supabase.co/functions/v1/send-message-push";

/** Mismo UUID que iOS: CrmChatService.stableUUID(for: "conv:\(id)"). */
export function stableThreadUUID(conversationId) {
  const hash = crypto.createHash("sha256").update(`conv:${conversationId}`).digest();
  const bytes = Uint8Array.from(hash.subarray(0, 16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Buffer.from(bytes).toString("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

function pushHeaders() {
  const headers = { "Content-Type": "application/json" };
  const secret = (process.env.PUSH_WEBHOOK_SECRET || "").trim();
  if (secret) headers["x-push-secret"] = secret;
  const serviceKey = (process.env.SUPABASE_SERVICE_ROLE_KEY || "").trim();
  if (serviceKey) {
    headers.Authorization = `Bearer ${serviceKey}`;
    headers.apikey = serviceKey;
  }
  return headers;
}

/**
 * @param {{ conversationId: string, text: string, contactName?: string | null, contactPhotoUrl?: string | null }} msg
 * @returns {Promise<{ ok: boolean, status?: number, detail?: string }>}
 */
export async function notifyInstagramIncomingMessage(msg) {
  const pushUrl = (process.env.SUPABASE_PUSH_FUNCTION_URL || DEFAULT_PUSH_URL).trim();
  if (!pushUrl) {
    console.warn("[crm-push] SUPABASE_PUSH_FUNCTION_URL missing");
    return { ok: false, detail: "missing_push_url" };
  }

  const conv = getConversation(msg.conversationId);
  const title =
    (msg.contactName || conv?.contact_name || "Instagram").trim() || "Instagram";
  const preview = (msg.text || conv?.last_message || "Nuevo mensaje").trim();
  if (!preview) return { ok: false, detail: "empty_preview" };

  const threadId = stableThreadUUID(msg.conversationId);
  const payload = {
    kind: "crm_lead",
    title,
    body: preview,
    thread_id: threadId,
    avatar_url: msg.contactPhotoUrl || conv?.contact_photo_url || null,
  };

  try {
    const res = await fetch(pushUrl, {
      method: "POST",
      headers: pushHeaders(),
      body: JSON.stringify(payload),
    });
    const detail = await res.text();
    if (!res.ok) {
      console.warn("[crm-push] push failed", res.status, detail.slice(0, 400));
      return { ok: false, status: res.status, detail };
    }
    console.info("[crm-push] push sent", threadId, detail.slice(0, 200));
    return { ok: true, status: res.status, detail };
  } catch (err) {
    console.warn("[crm-push]", err?.message || err);
    return { ok: false, detail: String(err?.message || err) };
  }
}
