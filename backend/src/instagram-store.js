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

export function ingestInstagramWebhook(body) {
  const store = ensureLoaded();
  let added = 0;

  const entries = Array.isArray(body?.entry) ? body.entry : [];
  for (const entry of entries) {
    const messaging = Array.isArray(entry.messaging)
      ? entry.messaging
      : Array.isArray(entry.standby)
        ? entry.standby
        : [];

    for (const event of messaging) {
      const message = event.message;
      if (!message) continue;

      const isEcho = Boolean(message.is_echo);
      // Incoming: sender is the customer. Echo: recipient is the customer.
      const customerId = isEcho ? event.recipient?.id : event.sender?.id;
      const text = (message.text || "").trim();
      const mid = message.mid || `${customerId}-${event.timestamp || Date.now()}`;
      if (!customerId) continue;

      // Skip empty non-attachment events
      const hasAttachment = Array.isArray(message.attachments) && message.attachments.length > 0;
      if (!text && !hasAttachment) continue;

      const convId = `ig:${customerId}`;
      const ts = Number(event.timestamp) || Date.now();
      const createdAt = nowISO(ts);

      if (!store.conversations[convId]) {
        store.conversations[convId] = {
          id: convId,
          contact_name: `Instagram · ${String(customerId).slice(-6)}`,
          contact_photo_url: null,
          last_message: "",
          unread_count: 0,
          updated_at: createdAt,
          contact_phone: null,
          wa_user_id: convId,
          source: "instagram",
          pinned: false,
          ai_active: false,
        };
      }

      if (!store.messages[convId]) store.messages[convId] = [];
      if (store.messages[convId].some((m) => m.id === mid)) continue;

      let mediaUrl = null;
      let mediaType = null;
      let messageType = "text";
      if (hasAttachment) {
        const att = message.attachments[0];
        messageType = att?.type || "image";
        mediaType = att?.type || null;
        mediaUrl = att?.payload?.url || null;
      }

      store.messages[convId].push({
        id: mid,
        text_content: text || (hasAttachment ? `[${messageType}]` : ""),
        sender_type: isEcho ? "agent" : "customer",
        created_at: createdAt,
        message_type: messageType,
        media_url: mediaUrl,
        media_type: mediaType,
        media_content: null,
        media_filename: null,
      });

      const conv = store.conversations[convId];
      conv.last_message = text || `[${messageType}]`;
      conv.updated_at = createdAt;
      if (!isEcho) {
        conv.unread_count = (conv.unread_count || 0) + 1;
      }
      added += 1;
    }
  }

  if (added > 0) persist();
  return added;
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

export function appendOutgoing(conversationId, text) {
  const store = ensureLoaded();
  if (!store.conversations[conversationId]) {
    store.conversations[conversationId] = {
      id: conversationId,
      contact_name: conversationId,
      contact_photo_url: null,
      last_message: text,
      unread_count: 0,
      updated_at: nowISO(),
      contact_phone: null,
      wa_user_id: conversationId,
      source: "instagram",
      pinned: false,
      ai_active: false,
    };
  }
  if (!store.messages[conversationId]) store.messages[conversationId] = [];
  const id = `out-${Date.now()}`;
  const createdAt = nowISO();
  store.messages[conversationId].push({
    id,
    text_content: text,
    sender_type: "agent",
    created_at: createdAt,
    message_type: "text",
    media_url: null,
    media_type: null,
    media_content: null,
    media_filename: null,
  });
  store.conversations[conversationId].last_message = text;
  store.conversations[conversationId].updated_at = createdAt;
  persist();
  return id;
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
