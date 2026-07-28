/**
 * Instagram Business Login (OAuth) — exchange code → short-lived → long-lived token.
 */
import {
  getInstagramIgUserId,
  saveInstagramPageToken,
} from "./instagram-token.js";

export function instagramOAuthRedirectUri() {
  const fromEnv = (process.env.INSTAGRAM_OAUTH_REDIRECT_URI || "").trim();
  if (fromEnv) return fromEnv;
  const base = (
    process.env.INSTAGRAM_WEBHOOK_PUBLIC_BASE_URL ||
    "https://smilestudio-backend.onrender.com"
  )
    .trim()
    .replace(/\/$/, "");
  return `${base}/api/instagram/oauth/callback`;
}

export function instagramAppId() {
  return (process.env.INSTAGRAM_APP_ID || "").trim();
}

export function instagramAppSecret() {
  return (process.env.INSTAGRAM_APP_SECRET || "").trim();
}

export function buildInstagramBusinessLoginUrl({
  scopes = [
    "instagram_business_basic",
    "instagram_business_manage_messages",
  ],
} = {}) {
  const clientId = instagramAppId();
  const redirectUri = instagramOAuthRedirectUri();
  if (!clientId) throw new Error("INSTAGRAM_APP_ID missing");

  const params = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: "code",
    scope: scopes.join(","),
  });
  return `https://www.instagram.com/oauth/authorize?${params.toString()}`;
}

async function exchangeCodeForShortLivedToken(code) {
  const clientId = instagramAppId();
  const clientSecret = instagramAppSecret();
  const redirectUri = instagramOAuthRedirectUri();
  if (!clientId || !clientSecret) {
    throw new Error("INSTAGRAM_APP_ID / INSTAGRAM_APP_SECRET missing");
  }

  const body = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    grant_type: "authorization_code",
    redirect_uri: redirectUri,
    code,
  });

  const res = await fetch("https://api.instagram.com/oauth/access_token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const json = await res.json();
  if (!res.ok || !json.access_token) {
    const msg = json?.error_message || json?.error?.message || JSON.stringify(json);
    throw new Error(`short_lived_token_failed: ${msg}`);
  }
  return {
    accessToken: json.access_token,
    userId: json.user_id ? String(json.user_id) : null,
    permissions: json.permissions || null,
  };
}

async function exchangeForLongLivedToken(shortLivedToken) {
  const clientSecret = instagramAppSecret();
  const qs = new URLSearchParams({
    grant_type: "ig_exchange_token",
    client_secret: clientSecret,
    access_token: shortLivedToken,
  });
  const res = await fetch(
    `https://graph.instagram.com/access_token?${qs.toString()}`
  );
  const json = await res.json();
  if (!res.ok || !json.access_token) {
    const msg = json?.error?.message || JSON.stringify(json);
    throw new Error(`long_lived_token_failed: ${msg}`);
  }
  return {
    accessToken: json.access_token,
    expiresIn: json.expires_in || null,
  };
}

async function fetchMe(accessToken) {
  const qs = new URLSearchParams({
    fields: "id,username,name,account_type",
    access_token: accessToken,
  });
  const res = await fetch(`https://graph.instagram.com/v21.0/me?${qs}`);
  const json = await res.json();
  if (!res.ok) return null;
  return json;
}

export async function handleInstagramOAuthCallback({ code, error, errorReason }) {
  if (error) {
    return {
      ok: false,
      message: errorReason || error || "login_denied",
    };
  }
  if (!code) {
    return { ok: false, message: "missing_code" };
  }

  // Meta sometimes appends #_ to the code.
  const cleanCode = String(code).replace(/#_+$/, "");

  const short = await exchangeCodeForShortLivedToken(cleanCode);
  let accessToken = short.accessToken;
  let expiresIn = null;
  try {
    const long = await exchangeForLongLivedToken(short.accessToken);
    accessToken = long.accessToken;
    expiresIn = long.expiresIn;
  } catch (err) {
    console.warn("[instagram/oauth] long-lived exchange failed:", err.message);
  }

  const me = await fetchMe(accessToken);
  const igUserId =
    (me?.id && String(me.id)) ||
    short.userId ||
    getInstagramIgUserId() ||
    null;

  const saved = saveInstagramPageToken({
    accessToken,
    igUserId,
    username: me?.username || null,
  });

  // Also mirror into process env for this running instance.
  process.env.INSTAGRAM_PAGE_ACCESS_TOKEN = accessToken;
  if (igUserId) process.env.INSTAGRAM_IG_USER_ID = igUserId;
  if (me?.username) process.env.INSTAGRAM_USERNAME = me.username;

  return {
    ok: true,
    username: me?.username || null,
    igUserId,
    expiresIn,
    tokenPreview: saved.tokenPreview,
  };
}
