/**
 * Guarda imágenes salientes en disco y expone URL pública para Meta Graph.
 */
import crypto from "crypto";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const OUTGOING_MEDIA_DIR = path.join(__dirname, "..", "data", "outgoing-media");

export function publicMediaBaseUrl(req) {
  const env = (process.env.INSTAGRAM_WEBHOOK_PUBLIC_BASE_URL || "").trim().replace(/\/$/, "");
  if (env) return `${env}/api/media/outgoing`;
  const proto = String(req?.headers?.["x-forwarded-proto"] || req?.protocol || "https").split(",")[0].trim();
  const host = String(req?.headers?.["x-forwarded-host"] || req?.get?.("host") || "").split(",")[0].trim();
  if (host) return `${proto}://${host}/api/media/outgoing`;
  return null;
}

function extensionForMime(mimeType = "image/jpeg") {
  const mime = String(mimeType).toLowerCase();
  if (mime.includes("png")) return "png";
  if (mime.includes("webp")) return "webp";
  if (mime.includes("gif")) return "gif";
  return "jpg";
}

export function saveOutgoingImageBase64(base64, mimeType = "image/jpeg") {
  const raw = String(base64 || "").trim();
  if (!raw) throw new Error("image_empty");
  const clean = raw.includes(",") ? raw.split(",").pop() : raw;
  const buf = Buffer.from(String(clean), "base64");
  if (buf.length < 64) throw new Error("image_too_small");
  if (buf.length > 12 * 1024 * 1024) throw new Error("image_too_large");

  const ext = extensionForMime(mimeType);
  const filename = `${crypto.randomUUID()}.${ext}`;
  fs.mkdirSync(OUTGOING_MEDIA_DIR, { recursive: true });
  fs.writeFileSync(path.join(OUTGOING_MEDIA_DIR, filename), buf);
  return { filename, mimeType, bytes: buf.length };
}

export function resolveOutgoingMediaPath(filename) {
  const safe = path.basename(String(filename || ""));
  if (!safe || safe !== filename) return null;
  const filePath = path.join(OUTGOING_MEDIA_DIR, safe);
  if (!fs.existsSync(filePath)) return null;
  return filePath;
}

export function mimeTypeForFilename(filename) {
  const ext = path.extname(String(filename || "")).toLowerCase();
  if (ext === ".png") return "image/png";
  if (ext === ".webp") return "image/webp";
  if (ext === ".gif") return "image/gif";
  return "image/jpeg";
}
