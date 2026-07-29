/**
 * Respuestas automáticas de IA para el CRM (Instagram DMs).
 * Detecta intención de pago y envía enlaces Square + Zelle + solicitud de comprobante.
 */
import { appendOutgoing, getConversation, listMessages } from "./instagram-store.js";
import { sendInstagramText } from "./instagram-webhook.js";

export const ZELLE_EMAIL =
  (process.env.CRM_ZELLE_EMAIL || "drgprivate@drgsmile.com").trim().toLowerCase();

export const SQUARE_CHECKOUT_LINKS = {
  vip: (
    process.env.CRM_SQUARE_VIP_URL ||
    "https://checkout.square.site/merchant/EJG2FZH297AY2/checkout/LVPNZ7VVI3FA6T7RVBNVZLPU?src=sheet"
  ).trim(),
  ortho: (
    process.env.CRM_SQUARE_ORTHO_URL ||
    "https://checkout.square.site/merchant/EJG2FZH297AY2/checkout/UD6FUVSIYJXPZLYPBB6IRNK5?src=sheet"
  ).trim(),
  limitedConcierge: (
    process.env.CRM_SQUARE_LIMITED_URL ||
    "https://checkout.square.site/merchant/EJG2FZH297AY2/checkout/SKC5GROJTH56NQPLVEYY5EAZ?src=sheet"
  ).trim(),
};

const PAYMENT_INTENT_PATTERNS = [
  /\bquiero pagar\b/i,
  /\bvoy a pagar\b/i,
  /\bhar[eé]\s+(?:el\s+)?pago\b/i,
  /\bhacer\s+(?:el\s+)?pago\b/i,
  /\bpagar(?:lo|la|le|les|me|te|se)?\s+hoy\b/i,
  /\bpago\s+hoy\b/i,
  /\bhoy\s+pago\b/i,
  /\bdeuda\s+pendiente\b/i,
  /\btengo\s+(?:una\s+)?deuda\b/i,
  /\bsaldo\s+pendiente\b/i,
  /\bcuenta\s+pendiente\b/i,
  /\bpendiente\s+de\s+pago\b/i,
  /\b(?:el|mi|un)\s+pago\b/i,
  /\bcomprobante\s+de\s+pago\b/i,
  /\benv[ií]o\s+(?:el\s+)?comprobante\b/i,
  /\bmando\s+(?:el\s+)?comprobante\b/i,
  /\btransferencia\b/i,
  /\bzelle\b/i,
  /\bpagar(?:e|é|ía|ia)?\b/i,
  /\brealizar(?:e|é)?\s+(?:el\s+)?pago\b/i,
  /\b(?:lunes|martes|mi[eé]rcoles|jueves|viernes|s[aá]bado|domingo|ma[nñ]ana)\s+(?:pago|pag(?:o|ar))\b/i,
  /\bpago\s+(?:el|este|pr[oó]ximo)?\s*(?:lunes|martes|mi[eé]rcoles|jueves|viernes|s[aá]bado|domingo|ma[nñ]ana)\b/i,
  /\b(?:vip|concierge|ortho|ortodoncia)\b/i,
  /\benlace\s+de\s+pago\b/i,
  /\blink\s+de\s+pago\b/i,
];

/** @param {string | null | undefined} text */
export function detectsPaymentIntent(text) {
  const t = String(text || "").trim();
  if (t.length < 3) return false;
  return PAYMENT_INTENT_PATTERNS.some((re) => re.test(t));
}

function isAiEnabled(conv) {
  if (!conv) return true;
  return conv.ai_active !== false;
}

function contactFirstName(contactName) {
  const raw = String(contactName || "").trim();
  if (!raw) return "";
  if (raw.startsWith("@")) return raw.slice(1);
  const part = raw.split("·").pop()?.trim() || raw;
  if (part.startsWith("@")) return part.slice(1);
  return part.split(/\s+/)[0] || part;
}

export function buildPaymentReply(contactName) {
  const name = contactFirstName(contactName);
  const hello = name ? `¡Hola, ${name}!` : "¡Hola!";
  const { vip, ortho, limitedConcierge } = SQUARE_CHECKOUT_LINKS;

  return `${hello} Gracias por avisarnos 🙏

Puedes pagar en línea con el enlace de tu servicio:

⭐ VIP Concierge
${vip}

🦷 Consulta Ortho
${ortho}

✨ Limited Concierge — Smile Studio Doral
${limitedConcierge}

También puedes pagar por Zelle:
📧 ${ZELLE_EMAIL}

Cuando pagues (Zelle o tarjeta), envíanos aquí el comprobante de pago para verificarlo.

Si no estás seguro cuál enlace usar, cuéntanos tu servicio y te guiamos 😊`;
}

function recentlySentPaymentReply(conversationId, withinMinutes = 45) {
  const msgs = listMessages(conversationId, 8);
  const cutoff = Date.now() - withinMinutes * 60 * 1000;
  for (let i = msgs.length - 1; i >= 0; i -= 1) {
    const m = msgs[i];
    if (m.sender_type === "customer") continue;
    const text = String(m.text_content || "").toLowerCase();
    const sentPaymentLinks =
      text.includes("checkout.square.site") || text.includes(ZELLE_EMAIL);
    if (!sentPaymentLinks) continue;
    const ts = Date.parse(m.created_at || "");
    if (!Number.isFinite(ts) || ts >= cutoff) return true;
    return false;
  }
  return false;
}

/** @deprecated use buildPaymentReply */
export function buildZellePaymentReply(contactName) {
  return buildPaymentReply(contactName);
}

/**
 * @param {{ conversationId: string, text: string, contactName?: string | null }} msg
 */
export async function maybeAutoReplyCrmMessage(msg) {
  const conversationId = String(msg.conversationId || "");
  const text = String(msg.text || "").trim();
  if (!conversationId || !text) {
    return { ok: false, skipped: true, reason: "empty" };
  }

  const conv = getConversation(conversationId);
  if (!isAiEnabled(conv)) {
    return { ok: false, skipped: true, reason: "ai_off" };
  }

  if (!detectsPaymentIntent(text)) {
    return { ok: false, skipped: true, reason: "no_payment_intent" };
  }

  if (recentlySentPaymentReply(conversationId)) {
    return { ok: false, skipped: true, reason: "already_sent_payment" };
  }

  const igsid = conversationId.startsWith("ig:") ? conversationId.slice(3) : null;
  if (!igsid) {
    return { ok: false, skipped: true, reason: "not_instagram" };
  }

  const reply = buildPaymentReply(msg.contactName || conv?.contact_name);
  try {
    const graph = await sendInstagramText({ igsid, text: reply });
    const messageId =
      graph?.message_id || graph?.messageId || graph?.id || null;
    appendOutgoing(conversationId, reply, messageId);
    console.info("[crm-ai] payment auto-reply sent", conversationId);
    return { ok: true, conversationId, intent: "payment_links" };
  } catch (err) {
    console.warn("[crm-ai] auto-reply failed", conversationId, err?.message || err);
    return {
      ok: false,
      error: err?.code || "auto_reply_failed",
      message: err?.message || "auto_reply_failed",
    };
  }
}
