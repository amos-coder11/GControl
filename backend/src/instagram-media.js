/**
 * Guarda imágenes/audio salientes en disco y expone URL pública para Meta Graph.
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
  if (mime.includes("ogg") || mime.includes("opus")) return "ogg";
  if (mime.includes("mpeg") || mime.includes("mp3")) return "mp3";
  if (mime.includes("aac")) return "aac";
  if (mime.includes("wav")) return "wav";
  if (mime.includes("audio") || mime.includes("mp4") || mime.includes("m4a")) return "m4a";
  return "jpg";
}

function saveOutgoingBase64(base64, mimeType, { minBytes, maxBytes, emptyCode, smallCode, largeCode }) {
  const raw = String(base64 || "").trim();
  if (!raw) throw new Error(emptyCode);
  const clean = raw.includes(",") ? raw.split(",").pop() : raw;
  const buf = Buffer.from(String(clean), "base64");
  if (buf.length < minBytes) throw new Error(smallCode);
  if (buf.length > maxBytes) throw new Error(largeCode);

  const ext = extensionForMime(mimeType);
  const filename = `${crypto.randomUUID()}.${ext}`;
  fs.mkdirSync(OUTGOING_MEDIA_DIR, { recursive: true });
  fs.writeFileSync(path.join(OUTGOING_MEDIA_DIR, filename), buf);
  return { filename, mimeType, bytes: buf.length };
}

export function saveOutgoingImageBase64(base64, mimeType = "image/jpeg") {
  return saveOutgoingBase64(base64, mimeType, {
    minBytes: 64,
    maxBytes: 12 * 1024 * 1024,
    emptyCode: "image_empty",
    smallCode: "image_too_small",
    largeCode: "image_too_large",
  });
}

export function saveOutgoingAudioBase64(base64, mimeType = "audio/mp4") {
  return saveOutgoingBase64(base64, mimeType, {
    minBytes: 200,
    maxBytes: 25 * 1024 * 1024,
    emptyCode: "audio_empty",
    smallCode: "audio_too_small",
    largeCode: "audio_too_large",
  });
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
  if (ext === ".m4a" || ext === ".mp4") return "audio/mp4";
  if (ext === ".mp3") return "audio/mpeg";
  if (ext === ".aac") return "audio/aac";
  if (ext === ".ogg" || ext === ".opus") return "audio/ogg";
  if (ext === ".wav") return "audio/wav";
  return "image/jpeg";
}
