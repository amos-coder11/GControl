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
  // Meta acepta m4a/mp4 para notas de voz; el grabador de iOS produce m4a.
  if (mime.includes("m4a") || mime.includes("mp4") || mime.includes("aac")) return "m4a";
  if (mime.includes("mpeg") || mime.includes("mp3")) return "mp3";
  if (mime.includes("wav")) return "wav";
  if (mime.includes("ogg") || mime.includes("opus")) return "ogg";
  return "jpg";
}

export function saveOutgoingImageBase64(base64, mimeType = "image/jpeg") {
  return saveOutgoingMediaBase64(base64, mimeType, { kind: "image" });
}

export function saveOutgoingAudioBase64(base64, mimeType = "audio/m4a") {
  return saveOutgoingMediaBase64(base64, mimeType, {
    kind: "audio",
    maxBytes: 25 * 1024 * 1024,
  });
}

export function saveOutgoingMediaBase64(
  base64,
  mimeType = "image/jpeg",
  { kind = "image", maxBytes = 12 * 1024 * 1024 } = {}
) {
  const raw = String(base64 || "").trim();
  if (!raw) throw new Error(`${kind}_empty`);
  const clean = raw.includes(",") ? raw.split(",").pop() : raw;
  const buf = Buffer.from(String(clean), "base64");
  if (buf.length < 64) throw new Error(`${kind}_too_small`);
  if (buf.length > maxBytes) throw new Error(`${kind}_too_large`);

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
  if (ext === ".m4a") return "audio/mp4";
  if (ext === ".mp3") return "audio/mpeg";
  if (ext === ".wav") return "audio/wav";
  if (ext === ".ogg") return "audio/ogg";
  return "image/jpeg";
}
