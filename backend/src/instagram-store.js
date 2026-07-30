/**
 * Persistencia simple de conversaciones/mensajes Instagram (archivo JSON).
 * Compatible con los endpoints que consume CrmChatService en iOS.
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.join(__dirname, "..", "data");
const STORE_PATH = path.join(DATA_DIR, "instagram-inbox.json");

function emptyStore() {
  return { conversations: {}, messages: {} };
}

function ensureLoaded() {
  if (!globalThis.__igStore) {
    try {
      fs.mkdirSync(DATA_DIR, { recursive: true });
      if (fs.existsSync(STORE_PATH)) {
        globalThis.__igStore = JSON.parse(fs.readFileSync(STORE_PATH, "utf8"));
      } else {
        globalThis.__igStore = emptyStore();
      }
    } catch (err) {
      console.warn("[instagram-store] load failed:", err.message);
      globalThis.__igStore = emptyStore();
    }
  }
  return globalThis.__igStore;
}

function persist() {
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true });
    fs.writeFileSync(STORE_PATH, JSON.stringify(globalThis.__igStore, null, 2));
  } catch (err) {
    console.warn("[instagram-store] persist failed:", err.message);
  }
}

function nowISO(ms = Date.now()) {
  return new Date(ms).toISOString();
}

/** Vacía la bandeja local (para rehacer un sync desde cero). */
export function resetInstagramStore() {
  const before = Object.keys(ensureLoaded().conversations).length;
  globalThis.__igStore = emptyStore();
  persist();
  return { cleared: before };
}

export function ensureConversation(convId, patch = {}) {
  const store = ensureLoaded();
  if (!store.conversations[convId]) {
    store.conversations[convId] = {
      id: convId,
      contact_name: patch.contact_name || `Instagram · ${String(convId).replace(/^ig:/, "").slice(-6)}`,
      contact_photo_url: patch.contact_photo_url || null,
      last_message: patch.last_message || "",
      unread_count: patch.unread_count || 0,
      updated_at: patch.updated_at || nowISO(),
      contact_phone: null,
      wa_user_id: convId,
      source: "instagram",
      pinned: false,
      ai_active: true,
    };
  } else {
    Object.assign(store.conversations[convId], Object.fromEntries(
      Object.entries(patch).filter(([, v]) => v !== undefined && v !== null && v !== "")
    ));
  }
  if (!store.messages[convId]) store.messages[convId] = [];
  persist();
  return store.conversations[convId];
}

export function updateConversationProfile(conversationId, { contact_name, contact_photo_url } = {}) {
  const store = ensureLoaded();
  const conv = store.conversations[conversationId];
  if (!conv) return false;
  if (contact_name) conv.contact_name = contact_name;
  if (contact_photo_url) conv.contact_photo_url = contact_photo_url;
  persist();
  return true;
}

/** @returns {boolean} true if inserted */
export function upsertMessage(conversationId, message, { bumpUnread = true } = {}) {
  const store = ensureLoaded();
  ensureConversation(conversationId);
  if (!store.messages[conversationId]) store.messages[conversationId] = [];
  if (store.messages[conversationId].some((m) => m.id === message.id)) return false;

  store.messages[conversationId].push({
    id: message.id,
    text_content: message.text_content || "",
    sender_type: message.sender_type || "customer",
    created_at: message.created_at || nowISO(),
    message_type: message.message_type || "text",
    media_url: message.media_url || null,
    media_type: message.media_type || null,
    media_content: message.media_content || null,
    media_filename: message.media_filename || null,
  });

  const conv = store.conversations[conversationId];
  conv.last_message = message.text_content || conv.last_message || "";
  conv.updated_at = message.created_at || nowISO();
  if (bumpUnread && message.sender_type !== "agent") {
    conv.unread_count = (conv.unread_count || 0) + 1;
  }
  persist();
  return true;
}

function extractMessagingEvents(body) {
  const events = [];
  const entries = Array.isArray(body?.entry) ? body.entry : [];
  for (const entry of entries) {
    if (Array.isArray(entry.messaging)) {
      for (const event of entry.messaging) events.push(event);
    }
    if (Array.isArray(entry.standby)) {
      for (const event of entry.standby) events.push(event);
    }
    // Algunos webhooks Instagram llegan como changes[].value
    if (Array.isArray(entry.changes)) {
      for (const change of entry.changes) {
        const value = change?.value;
        if (!value) continue;
        if (value.message || value.sender) {
          events.push(value);
        } else if (Array.isArray(value.messaging)) {
          events.push(...value.messaging);
        }
      }
    }
  }
  return events;
}

/**
 * @returns {{ added: number, customerIds: string[], incoming: Array<{ conversationId: string, text: string, contactName: string | null }> }}
 */
export function ingestInstagramWebhook(body) {
  const events = extractMessagingEvents(body);
  let added = 0;
  const customerIds = new Set();
  /** @type {Array<{ conversationId: string, text: string, contactName: string | null }>} */
  const incoming = [];

  for (const event of events) {
    const message = event.message;
    if (!message) continue;

    const isEcho = Boolean(message.is_echo);
    const customerId = isEcho ? event.recipient?.id : event.sender?.id;
    const text = (message.text || "").trim();
    const mid = message.mid || `${customerId}-${event.timestamp || Date.now()}`;
    if (!customerId) continue;

    const hasAttachment = Array.isArray(message.attachments) && message.attachments.length > 0;
    if (!text && !hasAttachment) continue;

    const convId = `ig:${customerId}`;
    const ts = Number(event.timestamp) || Date.now();
    const createdAt = nowISO(ts);

    ensureConversation(convId, { updated_at: createdAt });

    let mediaUrl = null;
    let mediaType = null;
    let messageType = "text";
    if (hasAttachment) {
      const att = message.attachments[0];
      messageType = att?.type || "image";
      mediaType = att?.type || null;
      mediaUrl = att?.payload?.url || null;
    }

    const inserted = upsertMessage(convId, {
      id: mid,
      text_content: text || (hasAttachment ? `[${messageType}]` : ""),
      sender_type: isEcho ? "agent" : "customer",
      created_at: createdAt,
      message_type: messageType,
      media_url: mediaUrl,
      media_type: mediaType,
    });
    if (inserted) {
      added += 1;
      if (!isEcho) {
        customerIds.add(String(customerId));
        const conv = getConversation(convId);
        incoming.push({
          conversationId: convId,
          text: text || (hasAttachment ? `[${messageType}]` : "Nuevo mensaje"),
          contactName: conv?.contact_name || null,
        });
      }
    }
  }

  return { added, customerIds: [...customerIds], incoming };
}

export function listConversations(limit = 100) {
  const store = ensureLoaded();
  return Object.values(store.conversations)
    .sort((a, b) => String(b.updated_at).localeCompare(String(a.updated_at)))
    .slice(0, limit);
}

export function listMessages(conversationId, limit = 100) {
  const store = ensureLoaded();
  const rows = store.messages[conversationId] || [];
  return rows.slice(-limit);
}

export function getConversation(conversationId) {
  const store = ensureLoaded();
  return store.conversations[conversationId] || null;
}

export function appendOutgoing(conversationId, text, messageId = null) {
  const id = messageId ? String(messageId) : `out-${Date.now()}`;
  upsertMessage(conversationId, {
    id,
    text_content: text,
    sender_type: "agent",
    created_at: nowISO(),
    message_type: "text",
  });
  return id;
}

export function appendOutgoingMedia(
  conversationId,
  {
    text = "",
    messageId = null,
    mediaUrl = null,
    mediaType = "image/jpeg",
    mediaContent = null,
    messageType = "image",
  } = {}
) {
  const id = messageId ? String(messageId) : `out-${Date.now()}`;
  const preview = String(text || "").trim() || (messageType === "image" ? "📷 Foto" : "📎 Archivo");
  upsertMessage(conversationId, {
    id,
    text_content: preview,
    sender_type: "agent",
    created_at: nowISO(),
    message_type: messageType,
    media_url: mediaUrl,
    media_type: mediaType,
    media_content: mediaContent,
  });
  return id;
}

/** Marca la conversación como leída (sin mensajes pendientes). */
export function markConversationRead(conversationId) {
  const store = ensureLoaded();
  const conv = store.conversations[conversationId];
  if (!conv) return false;
  conv.unread_count = 0;
  persist();
  return true;
}

export function setAiActive(conversationId, active) {
  const store = ensureLoaded();
  if (store.conversations[conversationId]) {
    store.conversations[conversationId].ai_active = Boolean(active);
    persist();
  }
}

export function setAllAiActive(active) {
  const store = ensureLoaded();
  for (const conv of Object.values(store.conversations)) {
    conv.ai_active = Boolean(active);
  }
  persist();
}
