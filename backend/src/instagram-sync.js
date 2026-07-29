/**
 * Sync Instagram DMs from Graph + enrich contact name/photo.
 */
import {
  explainGraphError,
  graphRequest,
  selfNode,
} from "./instagram-graph.js";
import {
  getInstagramIgUserId,
  getInstagramPageAccessToken,
  getInstagramUsername,
} from "./instagram-token.js";
import {
  ensureConversation,
  upsertMessage,
  updateConversationProfile,
  listConversations,
} from "./instagram-store.js";

const recentWebhookEvents = [];

export function rememberWebhookEvent(summary) {
  recentWebhookEvents.unshift({
    at: new Date().toISOString(),
    ...summary,
  });
  if (recentWebhookEvents.length > 30) recentWebhookEvents.length = 30;
}

export function getRecentWebhookEvents() {
  return recentWebhookEvents.slice(0, 20);
}

const SYNC_MIN_INTERVAL_MS = 60_000;
let lastSyncAt = 0;
let inFlightSync = null;

/**
 * Sync pensado para el polling de la app: un ciclo completo tarda ~2 min
 * (cientos de llamadas a Graph) y iOS pregunta cada 8 s, así que hacerlo en
 * cada petición dejaba la bandeja inservible.
 *
 * Solo espera cuando no hay nada que enseñar todavía; el resto de las veces
 * devuelve lo que ya hay y refresca por detrás.
 */
export async function syncInstagramInboxThrottled({ limit = 50 } = {}) {
  const hasData = listConversations(1).length > 0;
  const fresh = Date.now() - lastSyncAt < SYNC_MIN_INTERVAL_MS;

  if (hasData && (fresh || inFlightSync)) {
    return { skipped: true, reason: fresh ? "recently_synced" : "in_flight" };
  }

  if (!inFlightSync) {
    inFlightSync = syncInstagramInboxFromGraph({ limit })
      .catch((err) => {
        console.warn("[instagram/sync]", err?.message || err);
        return { synced: 0, error: err?.message || "sync_failed" };
      })
      .finally(() => {
        lastSyncAt = Date.now();
        inFlightSync = null;
      });
  }

  // Primera carga: sin datos que devolver, merece la pena esperar.
  if (!hasData) return await inFlightSync;
  return { skipped: true, reason: "background" };
}

async function graphGet(path, query = {}) {
  const res = await graphRequest(path, { query });
  if (!res.ok) {
    const err = new Error(res.error?.message || "graph_request_failed");
    err.details = res.error;
    err.explain = explainGraphError(res.error);
    throw err;
  }
  return res.json;
}

export async function resolveInstagramBusinessId() {
  const configured = getInstagramIgUserId();
  try {
    const me = await graphGet(selfNode(), { fields: "id,username" });
    if (me?.id) return String(me.id);
  } catch {
    // fall through
  }
  return configured;
}

export async function fetchInstagramUserProfile(igsid) {
  if (!igsid) return null;
  // profile_pic es el campo de Instagram Login; name/username pueden faltar.
  const fieldSets = ["name,username,profile_pic", "username,profile_pic", "username"];
  for (const fields of fieldSets) {
    const res = await graphRequest(String(igsid), { query: { fields } });
    if (res.ok) {
      return {
        name: res.json?.name || null,
        username: res.json?.username || null,
        profilePic: res.json?.profile_pic || res.json?.profile_picture_url || null,
      };
    }
  }
  return null;
}

export async function enrichConversationProfile(conversationId, igsid) {
  const profile = await fetchInstagramUserProfile(igsid);
  if (!profile) return null;
  const display =
    (profile.username ? `@${profile.username}` : null) ||
    profile.name ||
    null;
  updateConversationProfile(conversationId, {
    contact_name: display,
    contact_photo_url: profile.profilePic,
  });
  return profile;
}

/**
 * Lista conversaciones probando varios juegos de campos: Instagram Login no
 * soporta los mismos que Messenger Platform, y una versión rechaza toda la
 * llamada si un solo campo no existe.
 */
async function fetchConversationsPage(node, limit) {
  const attempts = [
    {
      limit: String(limit),
      fields:
        "id,updated_time,participants,messages.limit(30){id,created_time,from,to,message}",
    },
    { limit: String(limit), fields: "id,updated_time,participants" },
    { limit: String(limit) },
  ];

  let lastError = null;
  for (const query of attempts) {
    const res = await graphRequest(`${node}/conversations`, { query });
    if (res.ok) return { page: res.json, usedFields: query.fields || null };
    lastError = res.error;
    // Un bloqueo de acceso no se arregla quitando campos: aborta ya.
    if (explainGraphError(res.error)?.cause === "instagram_message_access_off") break;
  }

  const err = new Error(lastError?.message || "conversations_fetch_failed");
  err.details = lastError;
  err.explain = explainGraphError(lastError);
  throw err;
}

/** Mensajes de una conversación cuando la expansión anidada no vino incluida. */
async function fetchConversationMessages(conversationId) {
  const res = await graphRequest(conversationId, {
    query: { fields: "messages.limit(30){id,created_time,from,to,message}" },
  });
  if (res.ok) return res.json?.messages?.data || [];

  const flat = await graphRequest(`${conversationId}/messages`, {
    query: { fields: "id,created_time,from,to,message", limit: "30" },
  });
  return flat.ok ? flat.json?.data || [] : [];
}

/**
 * La misma cuenta aparece con dos IDs distintos: `me.id` devuelve el ID
 * app-scoped, mientras que `participants` y `from` usan el IG Business account
 * ID. Comparar contra uno solo hace que el negocio se tome por el cliente y
 * todas las conversaciones colapsen en una.
 */
function buildSelfIdentity(meId) {
  const ids = new Set(
    [meId, getInstagramIgUserId()].filter(Boolean).map(String)
  );
  const username = (getInstagramUsername() || "").trim().toLowerCase();
  return {
    isSelf(participant) {
      if (!participant) return false;
      if (participant.id && ids.has(String(participant.id))) return true;
      const name = String(participant.username || "").toLowerCase();
      return Boolean(username && name && name === username);
    },
    /** Aprende IDs nuevos de la cuenta al reconocerla por username. */
    learn(participant) {
      if (participant?.id) ids.add(String(participant.id));
    },
  };
}

/** Rellena el texto de mensajes que la expansión anidada devolvió vacío. */
async function backfillMessageText(messages, cap = 12) {
  const missing = messages.filter((m) => m.id && !(m.message || "").trim());
  if (missing.length === 0) return;

  // Prioriza los más recientes: son los que se ven como preview en la bandeja.
  const targets = missing
    .slice()
    .sort((a, b) =>
      String(b.created_time || "").localeCompare(String(a.created_time || ""))
    )
    .slice(0, cap);
  await Promise.all(
    targets.map(async (msg) => {
      const res = await graphRequest(msg.id, {
        query: { fields: "id,created_time,from,to,message" },
      });
      if (res.ok && res.json) {
        if (res.json.message) msg.message = res.json.message;
        if (!msg.from && res.json.from) msg.from = res.json.from;
        if (!msg.created_time && res.json.created_time) {
          msg.created_time = res.json.created_time;
        }
      }
    })
  );
}

/** Participantes de una conversación cuando no vinieron en la lista. */
async function fetchConversationParticipants(conversationId) {
  const res = await graphRequest(conversationId, { query: { fields: "participants" } });
  if (!res.ok) return [];
  const p = res.json?.participants;
  return p?.data || (Array.isArray(p) ? p : []);
}

/**
 * Pull conversations/messages from Instagram Graph into local store.
 * Also useful when webhooks are delayed.
 */
export async function syncInstagramInboxFromGraph({ limit = 25 } = {}) {
  const token = getInstagramPageAccessToken();
  if (!token) {
    return { synced: 0, reason: "token_missing" };
  }

  const node = selfNode();
  const igUserId = (await resolveInstagramBusinessId()) || getInstagramIgUserId();
  if (!igUserId) {
    return { synced: 0, reason: "ig_user_id_missing" };
  }

  const { page, usedFields } = await fetchConversationsPage(
    node,
    Math.min(limit, 50)
  );

  const rows = Array.isArray(page?.data) ? page.data : [];
  const nestedMessages = Boolean(usedFields && usedFields.includes("messages"));
  const nestedParticipants = Boolean(usedFields && usedFields.includes("participants"));
  const self = buildSelfIdentity(igUserId);

  let synced = 0;
  let skipped = 0;
  for (const conv of rows) {
    let participants = conv.participants?.data || conv.participants || [];
    if (!nestedParticipants || !Array.isArray(participants) || participants.length === 0) {
      participants = await fetchConversationParticipants(conv.id);
    }
    const participantList = Array.isArray(participants) ? participants : [];
    participantList.filter((p) => self.isSelf(p)).forEach((p) => self.learn(p));

    const other = participantList.find((p) => !self.isSelf(p));
    if (!other?.id) {
      skipped += 1;
      continue;
    }

    const customerId = String(other.id);
    const convId = `ig:${customerId}`;
    const display =
      (other.username ? `@${other.username}` : null) ||
      other.name ||
      `Instagram · ${customerId.slice(-6)}`;

    ensureConversation(convId, {
      contact_name: display,
      updated_at: conv.updated_time || new Date().toISOString(),
    });

    let messages = conv.messages?.data || [];
    if (!nestedMessages || messages.length === 0) {
      messages = await fetchConversationMessages(conv.id);
    }
    await backfillMessageText(messages);

    for (const msg of messages) {
      const isOutgoing = self.isSelf(msg.from);
      const text = (msg.message || "").trim();
      if (!text && !msg.id) continue;
      const added = upsertMessage(
        convId,
        {
          id: msg.id || `${convId}-${msg.created_time}`,
          text_content: text || "[archivo adjunto]",
          sender_type: isOutgoing ? "agent" : "customer",
          created_at: msg.created_time || new Date().toISOString(),
          message_type: "text",
        },
        { bumpUnread: false }
      );
      if (added) synced += 1;
    }

    // La foto de perfil no viene en participants; el username sí, así que el
    // nombre ya es correcto aunque esta llamada falle.
    await enrichConversationProfile(convId, customerId);
  }

  return {
    synced,
    conversations: listConversations(limit).length,
    igUserId,
    graphCount: rows.length,
    skipped,
    usedFields,
  };
}
