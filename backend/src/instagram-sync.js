/**
 * Sync Instagram DMs from Graph + enrich contact name/photo.
 */
import {
  getInstagramIgUserId,
  getInstagramPageAccessToken,
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

async function graphGet(path, query = {}) {
  const token = getInstagramPageAccessToken();
  if (!token) throw new Error("instagram_page_token_missing");

  const qs = new URLSearchParams({ ...query, access_token: token });
  const hosts = ["https://graph.instagram.com", "https://graph.facebook.com"];
  let lastErr = null;
  for (const host of hosts) {
    try {
      const url = `${host}/v21.0/${path}?${qs.toString()}`;
      const res = await fetch(url);
      const text = await res.text();
      let json = null;
      try {
        json = text ? JSON.parse(text) : null;
      } catch {
        json = { raw: text.slice(0, 400) };
      }
      if (res.ok) return json;
      lastErr = json?.error?.message || `graph_${res.status}`;
      // IGAA tokens only work on graph.instagram.com
      if (token.startsWith("IGAA")) break;
    } catch (err) {
      lastErr = String(err?.message || err);
    }
  }
  throw new Error(lastErr || "graph_request_failed");
}

export async function resolveInstagramBusinessId() {
  const configured = getInstagramIgUserId();
  try {
    const me = await graphGet("me", { fields: "id,username,name" });
    if (me?.id) return String(me.id);
  } catch {
    // fall through
  }
  return configured;
}

export async function fetchInstagramUserProfile(igsid) {
  if (!igsid) return null;
  try {
    const profile = await graphGet(String(igsid), {
      fields: "name,username,profile_pic",
    });
    return {
      name: profile?.name || null,
      username: profile?.username || null,
      profilePic: profile?.profile_pic || null,
    };
  } catch (err) {
    console.warn("[instagram/profile]", igsid, err?.message || err);
    return null;
  }
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
 * Pull conversations/messages from Instagram Graph into local store.
 * Also useful when webhooks are delayed.
 */
export async function syncInstagramInboxFromGraph({ limit = 25 } = {}) {
  const token = getInstagramPageAccessToken();
  if (!token) {
    return { synced: 0, reason: "token_missing" };
  }

  const igUserId = await resolveInstagramBusinessId();
  if (!igUserId) {
    return { synced: 0, reason: "ig_user_id_missing" };
  }

  let synced = 0;
  let urlPath = `${igUserId}/conversations`;
  let query = {
    platform: "instagram",
    limit: String(Math.min(limit, 50)),
    fields:
      "id,updated_time,participants{id,username,name},messages.limit(30){id,created_time,from,to,message}",
  };

  // One page is enough for inbox MVP; follow next once if empty weirdness.
  let page = await graphGet(urlPath, query);
  if ((!page?.data || page.data.length === 0) && page?.paging?.next) {
    try {
      const res = await fetch(page.paging.next);
      page = await res.json();
    } catch {
      // ignore
    }
  }

  const rows = Array.isArray(page?.data) ? page.data : [];
  for (const conv of rows) {
    const participants = conv.participants?.data || conv.participants || [];
    const participantList = Array.isArray(participants) ? participants : [];
    const other =
      participantList.find((p) => String(p.id) !== String(igUserId)) ||
      participantList[0];
    if (!other?.id) continue;

    const customerId = String(other.id);
    const convId = `ig:${customerId}`;
    const display =
      (other.username ? `@${other.username}` : null) ||
      other.name ||
      `Instagram · ${customerId.slice(-6)}`;

    ensureConversation(convId, {
      contact_name: display,
      contact_photo_url: null,
      updated_at: conv.updated_time || new Date().toISOString(),
    });

    const messages = conv.messages?.data || [];
    for (const msg of messages) {
      const fromId = String(msg.from?.id || "");
      const isOutgoing = fromId && fromId === String(igUserId);
      const text = (msg.message || "").trim();
      if (!text && !msg.id) continue;
      const added = upsertMessage(
        convId,
        {
          id: msg.id || `${convId}-${msg.created_time}`,
          text_content: text || "[message]",
          sender_type: isOutgoing ? "agent" : "customer",
          created_at: msg.created_time || new Date().toISOString(),
          message_type: "text",
        },
        { bumpUnread: false }
      );
      if (added) synced += 1;
    }

    // Profile photo enrichment
    await enrichConversationProfile(convId, customerId);
  }

  // If Graph returned no threads, still return local count for transparency.
  return {
    synced,
    conversations: listConversations(limit).length,
    igUserId,
    graphCount: rows.length,
  };
}
