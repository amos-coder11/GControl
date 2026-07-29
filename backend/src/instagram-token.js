/**
 * Token de Instagram Messaging (Page Access Token EAAB… o Instagram User Token IGAA…).
 * Persistido en disco o vía env.
 */
import crypto from "crypto";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.join(__dirname, "..", "data");
const TOKEN_PATH = path.join(DATA_DIR, "instagram-page-token.json");

function readFile() {
  try {
    if (!fs.existsSync(TOKEN_PATH)) return null;
    return JSON.parse(fs.readFileSync(TOKEN_PATH, "utf8"));
  } catch {
    return null;
  }
}

export function getInstagramPageAccessToken() {
  const fromEnv = (
    process.env.INSTAGRAM_PAGE_ACCESS_TOKEN ||
    process.env.INSTAGRAM_ACCESS_TOKEN ||
    ""
  ).trim();
  if (fromEnv) return fromEnv;
  return String(readFile()?.accessToken || "").trim() || null;
}

export function getInstagramPageId() {
  const fromEnv = (process.env.INSTAGRAM_PAGE_ID || "").trim();
  if (fromEnv) return fromEnv;
  return String(readFile()?.pageId || "").trim() || null;
}

export function getInstagramIgUserId() {
  const fromEnv = (process.env.INSTAGRAM_IG_USER_ID || "").trim();
  if (fromEnv) return fromEnv;
  return String(readFile()?.igUserId || "").trim() || null;
}

export function getInstagramUsername() {
  const fromEnv = (process.env.INSTAGRAM_USERNAME || "").trim();
  if (fromEnv) return fromEnv;
  return String(readFile()?.username || "").trim() || null;
}

export function saveInstagramPageToken({
  accessToken,
  pageId,
  igUserId,
  username,
} = {}) {
  let token = String(accessToken || "").trim();
  let igId = String(igUserId || "").trim() || null;
  let page = String(pageId || "").trim() || null;
  let user = String(username || "").trim() || null;

  // Meta a veces entrega "IG_USER_ID=TOKEN"
  if (token.includes("=") && !token.startsWith("EAA") && !token.startsWith("IGAA")) {
    const idx = token.indexOf("=");
    const left = token.slice(0, idx).trim();
    const right = token.slice(idx + 1).trim();
    if (/^\d+$/.test(left) && right) {
      igId = igId || left;
      token = right;
    }
  }

  if (!token) throw new Error("access_token_required");
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const payload = {
    accessToken: token,
    pageId: page,
    igUserId: igId,
    username: user,
    savedAt: new Date().toISOString(),
  };
  fs.writeFileSync(TOKEN_PATH, JSON.stringify(payload, null, 2));
  return {
    saved: true,
    pageId: payload.pageId,
    igUserId: payload.igUserId,
    username: payload.username,
    tokenPreview: `${token.slice(0, 8)}…${token.slice(-4)}`,
  };
}

/**
 * Devuelve el token completo solo si `secret` coincide con INSTAGRAM_ADMIN_SECRET.
 *
 * El disco de Render free es efímero: el token que guarda el OAuth se pierde en
 * cada reinicio. Esto permite recuperarlo una vez y fijarlo como variable de
 * entorno, que sí sobrevive. Deja INSTAGRAM_ADMIN_SECRET sin definir para
 * desactivar el endpoint por completo.
 */
export function exportInstagramToken(secret) {
  const expected = (process.env.INSTAGRAM_ADMIN_SECRET || "").trim();
  if (!expected) {
    return { ok: false, status: 404, error: "export_disabled" };
  }

  const given = String(secret || "");
  const a = Buffer.from(given);
  const b = Buffer.from(expected);
  const match = a.length === b.length && crypto.timingSafeEqual(a, b);
  if (!match) {
    console.warn("[instagram/export-token] rejected");
    return { ok: false, status: 403, error: "forbidden" };
  }

  const token = getInstagramPageAccessToken();
  if (!token) {
    return { ok: false, status: 404, error: "token_missing" };
  }

  console.info("[instagram/export-token] token exported");
  return {
    ok: true,
    status: 200,
    accessToken: token,
    igUserId: getInstagramIgUserId(),
    username: getInstagramUsername(),
    note: "Guárdalo como INSTAGRAM_PAGE_ACCESS_TOKEN y borra INSTAGRAM_ADMIN_SECRET.",
  };
}

export function instagramSendStatus() {
  const token = getInstagramPageAccessToken();
  const isIgUserToken = Boolean(token && token.startsWith("IGAA"));
  return {
    pageTokenConfigured: Boolean(token),
    pageIdConfigured: Boolean(getInstagramPageId()),
    igUserIdConfigured: Boolean(getInstagramIgUserId()),
    username: getInstagramUsername(),
    tokenKind: token ? (isIgUserToken ? "instagram_user" : "page_or_other") : null,
    tokenPreview: token ? `${token.slice(0, 8)}…${token.slice(-4)}` : null,
  };
}
