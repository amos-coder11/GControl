/**
 * Page Access Token para enviar DMs de Instagram (persistido en disco).
 * También se puede inyectar con INSTAGRAM_PAGE_ACCESS_TOKEN.
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.join(__dirname, "..", "data");
const TOKEN_PATH = path.join(DATA_DIR, "instagram-page-token.json");

function readFileToken() {
  try {
    if (!fs.existsSync(TOKEN_PATH)) return null;
    const raw = JSON.parse(fs.readFileSync(TOKEN_PATH, "utf8"));
    const token = String(raw?.accessToken || "").trim();
    return token || null;
  } catch {
    return null;
  }
}

export function getInstagramPageAccessToken() {
  const fromEnv = (process.env.INSTAGRAM_PAGE_ACCESS_TOKEN || "").trim();
  if (fromEnv) return fromEnv;
  return readFileToken();
}

export function getInstagramPageId() {
  const fromEnv = (process.env.INSTAGRAM_PAGE_ID || "").trim();
  if (fromEnv) return fromEnv;
  try {
    if (!fs.existsSync(TOKEN_PATH)) return null;
    const raw = JSON.parse(fs.readFileSync(TOKEN_PATH, "utf8"));
    const id = String(raw?.pageId || "").trim();
    return id || null;
  } catch {
    return null;
  }
}

export function saveInstagramPageToken({ accessToken, pageId } = {}) {
  const token = String(accessToken || "").trim();
  if (!token) throw new Error("access_token_required");
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const payload = {
    accessToken: token,
    pageId: String(pageId || "").trim() || null,
    savedAt: new Date().toISOString(),
  };
  fs.writeFileSync(TOKEN_PATH, JSON.stringify(payload, null, 2));
  return {
    saved: true,
    pageId: payload.pageId,
    tokenPreview: `${token.slice(0, 8)}…${token.slice(-4)}`,
  };
}

export function instagramSendStatus() {
  const token = getInstagramPageAccessToken();
  return {
    pageTokenConfigured: Boolean(token),
    pageIdConfigured: Boolean(getInstagramPageId()),
    tokenPreview: token ? `${token.slice(0, 8)}…${token.slice(-4)}` : null,
  };
}
