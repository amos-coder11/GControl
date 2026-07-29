/**
 * Cliente Graph unificado para Instagram API with Instagram Login (tokens IGAA…)
 * y Messenger Platform con Page Access Token (EAAB…).
 *
 * Devuelve siempre el error crudo de Meta (code / error_subcode / message) para
 * poder diagnosticar sin adivinar.
 */
import {
  getInstagramPageAccessToken,
  getInstagramIgUserId,
} from "./instagram-token.js";

export const IG_HOST = "https://graph.instagram.com";
export const FB_HOST = "https://graph.facebook.com";
export const GRAPH_VERSION = (process.env.INSTAGRAM_GRAPH_VERSION || "v23.0").trim();

export function isInstagramLoginToken(token = getInstagramPageAccessToken()) {
  return Boolean(token && token.startsWith("IGAA"));
}

/** Host correcto según el tipo de token. */
export function defaultGraphHost() {
  return isInstagramLoginToken() ? IG_HOST : FB_HOST;
}

/**
 * Llamada cruda a Graph. Nunca lanza: devuelve { ok, status, json, error, url }.
 * El token viaja en header Authorization (no en la URL) para no filtrarlo en logs.
 */
export async function graphRequest(
  path,
  {
    method = "GET",
    query = {},
    body = null,
    host = defaultGraphHost(),
    version = GRAPH_VERSION,
    token = getInstagramPageAccessToken(),
  } = {}
) {
  if (!token) {
    return {
      ok: false,
      status: 0,
      json: null,
      error: { message: "instagram_page_token_missing" },
      url: null,
    };
  }

  const cleanPath = String(path).replace(/^\//, "");
  const qs = new URLSearchParams(
    Object.fromEntries(
      Object.entries(query).filter(([, v]) => v !== undefined && v !== null && v !== "")
    )
  );
  const url = `${host}/${version}/${cleanPath}${qs.toString() ? `?${qs}` : ""}`;

  const headers = { Authorization: `Bearer ${token}` };
  let payload;
  if (body) {
    headers["Content-Type"] = "application/json";
    payload = typeof body === "string" ? body : JSON.stringify(body);
  }

  try {
    const res = await fetch(url, { method, headers, body: payload });
    const text = await res.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = { raw: text.slice(0, 400) };
    }
    return {
      ok: res.ok,
      status: res.status,
      json,
      error: res.ok ? null : json?.error || { message: `graph_${res.status}` },
      url,
    };
  } catch (err) {
    return {
      ok: false,
      status: 0,
      json: null,
      error: { message: String(err?.message || err) },
      url,
    };
  }
}

/** Igual que graphRequest pero lanza Error con .details en fallo. */
export async function graphOrThrow(path, options = {}) {
  const res = await graphRequest(path, options);
  if (!res.ok) {
    const err = new Error(res.error?.message || `graph_${res.status}`);
    err.details = res.error;
    err.status = res.status;
    throw err;
  }
  return res.json;
}

/**
 * Nodo raíz de la cuenta: "me" para tokens IGAA, el IG User ID para Page tokens.
 */
export function selfNode() {
  if (isInstagramLoginToken()) return "me";
  return getInstagramIgUserId() || "me";
}

/**
 * Traduce los errores más comunes de Meta a una causa accionable en español.
 */
export function explainGraphError(error) {
  if (!error) return null;
  const code = Number(error.code);
  const sub = Number(error.error_subcode);
  const message = String(error.message || "");

  if (/API access blocked/i.test(message)) {
    return {
      cause: "instagram_message_access_off",
      hint:
        "Instagram tiene bloqueado el acceso a mensajes para apps. En la app de Instagram de @tu_cuenta: Configuración → Mensajes y respuestas de historias → Controles de mensajes → Herramientas conectadas → activa 'Permitir el acceso a los mensajes'. También revisa que la app tenga Acceso avanzado a instagram_business_manage_messages.",
    };
  }
  if (code === 190) {
    return {
      cause: "token_invalid_or_expired",
      hint: "El access token caducó o fue revocado. Vuelve a conectar en /api/instagram/login.",
    };
  }
  if (code === 10 || code === 200 || sub === 2534085) {
    return {
      cause: "missing_permission",
      hint:
        "Falta permiso o Acceso avanzado. En Meta → App Review → Permissions: instagram_business_basic + instagram_business_manage_messages.",
    };
  }
  if (code === 100 && /nonexisting field/i.test(message)) {
    return {
      cause: "unsupported_field",
      hint: "Campo no soportado por esta versión/tipo de token; se reintenta con menos campos.",
    };
  }
  if (code === 4 || code === 17 || code === 32) {
    return { cause: "rate_limited", hint: "Límite de peticiones de Meta. Reintenta en unos minutos." };
  }
  return { cause: "graph_error", hint: message };
}
