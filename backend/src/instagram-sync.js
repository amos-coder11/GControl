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
  const fieldSets = [
    "name,username,profile_pic,is_verified_user",
    "username,profile_pic,is_verified_user",
    "name,username,profile_pic",
    "username,profile_pic",
    "username",
  ];
  for (const fields of fieldSets) {
    const res = await graphRequest(String(igsid), { query: { fields } });
    if (res.ok) {
      return {
        name: res.json?.name || null,
        username: res.json?.username || null,
        profilePic: res.json?.profile_pic || res.json?.profile_picture_url || null,
        isVerified: Boolean(
          res.json?.is_verified_user ??
            res.json?.is_verified ??
            res.json?.verified
        ),
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
    contact_verified: profile.isVerified,
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

/**
 * Muchos DMs de un negocio no llevan texto: son respuestas a historias, fotos
 * o reacciones. Pedimos los adjuntos para poder etiquetarlos con algo legible
 * en vez de un marcador genérico, y para que la app pueda pintar la imagen.
 */
function describeAttachment(msg) {
  const raw = msg?.attachments;
  const att = raw?.data?.[0] || (Array.isArray(raw) ? raw[0] : null);
  if (!att) {
    // Buena parte de esta bandeja son menciones y respuestas a historias:
    // llegan sin `attachments`, con el enlace colgando de `story`.
    const storyLink =
      msg?.story?.mention?.link ||
      msg?.story?.reply_to?.link ||
      msg?.story?.link ||
      null;
    if (storyLink) {
      return { url: storyLink, type: "image", label: "📷 Historia" };
    }
    const shareLink = msg?.shares?.data?.[0]?.link || null;
    if (shareLink) {
      return { url: shareLink, type: "share", label: "🔗 Publicación" };
    }
    return null;
  }

  const url =
    att.image_data?.url ||
    att.video_data?.url ||
    att.audio_data?.url ||
    att.payload?.url ||
    att.file_url ||
    att.url ||
    att.image_data?.preview_url ||
    null;

  // Forma Messenger: { type: "audio" | "image" | ..., payload: { url } }
  const declared = String(att.type || "").toLowerCase();
  if (declared) {
    if (declared.includes("audio") || declared.includes("voice")) {
      return { url, type: "audio", label: "🎤 Audio" };
    }
    if (declared.includes("video") || declared.includes("reel")) {
      return { url, type: "video", label: "🎥 Vídeo" };
    }
    if (declared.includes("image") || declared.includes("photo")) {
      return { url, type: "image", label: "📷 Foto" };
    }
    if (declared.includes("story")) {
      return { url, type: "image", label: "📷 Historia" };
    }
    if (declared.includes("share")) {
      return { url, type: "share", label: "🔗 Publicación" };
    }
  }

  // La forma del adjunto varía: unas veces image_data/video_data, otras solo
  // mime_type + file_url, y a veces la pista está en la propia URL.
  const mime = String(att.mime_type || "").toLowerCase();
  const name = String(att.name || "").toLowerCase();
  const probe = `${mime} ${name} ${String(url || "").split("?")[0]}`.toLowerCase();

  const isImage =
    Boolean(att.image_data) ||
    mime.startsWith("image") ||
    /\.(jpe?g|png|gif|webp|heic)$/.test(probe);
  const isVideo =
    Boolean(att.video_data) ||
    mime.startsWith("video") ||
    /\.(mp4|mov|m4v|webm)$/.test(probe);
  const isAudio =
    mime.startsWith("audio") || /\.(mp3|m4a|ogg|wav|aac)$/.test(probe);

  let type = "file";
  let label = "📎 Archivo";
  if (isImage) {
    type = "image";
    label = "📷 Foto";
  } else if (isVideo) {
    type = "video";
    label = "🎥 Vídeo";
  } else if (isAudio) {
    type = "audio";
    label = "🎤 Audio";
  }

  return { url, type, label };
}

/** Rellena texto y adjuntos de los mensajes que vinieron vacíos. */
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

  const fieldSets = [
    "id,created_time,from,to,message,attachments,story,shares",
    "id,created_time,from,to,message,attachments",
    "id,created_time,from,to,message",
  ];

  await Promise.all(
    targets.map(async (msg) => {
      for (const fields of fieldSets) {
        const res = await graphRequest(msg.id, { query: { fields } });
        if (!res.ok) continue;
        const json = res.json || {};
        if (json.message) msg.message = json.message;
        if (json.attachments) msg.attachments = json.attachments;
        if (json.story) msg.story = json.story;
        if (json.shares) msg.shares = json.shares;
        if (!msg.from && json.from) msg.from = json.from;
        if (!msg.created_time && json.created_time) {
          msg.created_time = json.created_time;
        }
        break;
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
      const media = text ? null : describeAttachment(msg);
      const added = upsertMessage(
        convId,
        {
          id: msg.id || `${convId}-${msg.created_time}`,
          text_content: text || media?.label || "📎 Adjunto",
          sender_type: isOutgoing ? "agent" : "customer",
          created_at: msg.created_time || new Date().toISOString(),
          message_type: media ? media.type : "text",
          media_url: media?.url || null,
          media_type: media?.type || null,
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
