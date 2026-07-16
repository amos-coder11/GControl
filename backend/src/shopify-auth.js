import crypto from "crypto";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SESSION_PATH = path.join(__dirname, "..", ".shopify-session.json");
const ENV_PATH = path.join(__dirname, "..", ".env");

const DEFAULT_SCOPES = "read_orders,read_products,read_customers";

const pendingStates = new Map();

function shopDomain() {
  const raw = (process.env.SHOPIFY_SHOP || "").trim().toLowerCase();
  if (!raw) return null;
  return raw.endsWith(".myshopify.com") ? raw : `${raw}.myshopify.com`;
}

function shopHandle() {
  const domain = shopDomain();
  return domain?.replace(".myshopify.com", "") || null;
}

function redirectUri() {
  const fromEnv = (process.env.SHOPIFY_REDIRECT_URI || "").trim();
  if (fromEnv) return fromEnv;
  const port = process.env.PORT || 3000;
  return `http://127.0.0.1:${port}/api/shopify/callback`;
}

function scopes() {
  return (process.env.SHOPIFY_SCOPES || DEFAULT_SCOPES).trim();
}

export function loadShopifySession() {
  try {
    const raw = fs.readFileSync(SESSION_PATH, "utf8");
    const json = JSON.parse(raw);
    if (json?.accessToken && json?.shop) return json;
  } catch {
    // no session yet
  }
  return null;
}

function saveShopifySession(session) {
  fs.writeFileSync(SESSION_PATH, JSON.stringify(session, null, 2));
  persistAccessTokenInEnv(session.accessToken);
}

function persistAccessTokenInEnv(token) {
  try {
    let env = "";
    try {
      env = fs.readFileSync(ENV_PATH, "utf8");
    } catch {
      env = "";
    }

    const line = `SHOPIFY_ADMIN_ACCESS_TOKEN=${token}`;
    if (/^SHOPIFY_ADMIN_ACCESS_TOKEN=/m.test(env)) {
      env = env.replace(/^SHOPIFY_ADMIN_ACCESS_TOKEN=.*$/m, line);
    } else {
      env = `${env.trimEnd()}\n${line}\n`;
    }

    if (/^SHOPIFY_DEV_FIXTURE=/m.test(env)) {
      env = env.replace(/^SHOPIFY_DEV_FIXTURE=.*$/m, "SHOPIFY_DEV_FIXTURE=0");
    } else {
      env = `${env.trimEnd()}\nSHOPIFY_DEV_FIXTURE=0\n`;
    }

    fs.writeFileSync(ENV_PATH, env);
    process.env.SHOPIFY_ADMIN_ACCESS_TOKEN = token;
    process.env.SHOPIFY_DEV_FIXTURE = "0";
  } catch (err) {
    console.warn("[shopify-auth] no se pudo actualizar .env:", err.message);
  }
}

export function getInstalledAccessToken() {
  const fromEnv = (process.env.SHOPIFY_ADMIN_ACCESS_TOKEN || "").trim();
  if (fromEnv) return fromEnv;
  return loadShopifySession()?.accessToken || null;
}

export function buildInstallUrl() {
  const shop = shopDomain();
  const clientId = process.env.SHOPIFY_CLIENT_ID?.trim();
  if (!shop || !clientId) {
    throw new Error("shopify_install_missing_config");
  }

  const state = crypto.randomBytes(16).toString("hex");
  pendingStates.set(state, Date.now());

  const params = new URLSearchParams({
    client_id: clientId,
    scope: scopes(),
    redirect_uri: redirectUri(),
    state,
  });

  const adminInstallUrl = `https://admin.shopify.com/store/${shopHandle()}/oauth/install?client_id=${clientId}`;

  return {
    state,
    redirectUri: redirectUri(),
    scopes: scopes(),
    authorizeUrl: `https://${shop}/admin/oauth/authorize?${params.toString()}`,
    adminInstallUrl,
    preferredInstallUrl: adminInstallUrl,
  };
}

export function saveManualAccessToken(token) {
  const trimmed = (token || "").trim();
  if (!trimmed.startsWith("shpat_") && !trimmed.startsWith("shpua_")) {
    throw new Error("shopify_token_invalid_format");
  }

  const session = {
    shop: shopDomain(),
    accessToken: trimmed,
    scope: scopes(),
    installedAt: new Date().toISOString(),
    source: "manual_token",
  };

  saveShopifySession(session);
  return session;
}

function verifyState(state) {
  if (!state || !pendingStates.has(state)) return false;
  pendingStates.delete(state);
  return true;
}

export async function exchangeInstallCode(code) {
  const shop = shopDomain();
  const clientId = process.env.SHOPIFY_CLIENT_ID?.trim();
  const clientSecret = process.env.SHOPIFY_CLIENT_SECRET?.trim();

  if (!shop || !clientId || !clientSecret || !code) {
    throw new Error("shopify_install_exchange_missing_params");
  }

  const res = await fetch(`https://${shop}/admin/oauth/access_token`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({
      client_id: clientId,
      client_secret: clientSecret,
      code,
    }),
  });

  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`shopify_install_invalid_json:${text.slice(0, 200)}`);
  }

  if (!res.ok || !json.access_token) {
    const detail = json.error_description || json.error || text.slice(0, 200);
    throw new Error(`shopify_install_exchange_failed:${detail}`);
  }

  const session = {
    shop,
    accessToken: json.access_token,
    scope: json.scope || scopes(),
    installedAt: new Date().toISOString(),
  };

  saveShopifySession(session);
  return session;
}

export function handleInstallCallback(query) {
  const { code, state, shop, error, error_description: errorDescription } = query;

  if (error) {
    throw new Error(`shopify_install_denied:${errorDescription || error}`);
  }

  if (!verifyState(state)) {
    throw new Error("shopify_install_invalid_state");
  }

  if (!code) {
    throw new Error("shopify_install_missing_code");
  }

  if (shop && shop !== shopDomain()) {
    throw new Error(`shopify_install_shop_mismatch:${shop}`);
  }

  return exchangeInstallCode(code);
}

export function installStatus() {
  const session = loadShopifySession();
  const token = getInstalledAccessToken();
  return {
    installed: Boolean(token),
    shop: shopDomain(),
    scopes: session?.scope || scopes(),
    installedAt: session?.installedAt || null,
    redirectUri: redirectUri(),
    adminInstallUrl: shopHandle() && process.env.SHOPIFY_CLIENT_ID
      ? `https://admin.shopify.com/store/${shopHandle()}/oauth/install?client_id=${process.env.SHOPIFY_CLIENT_ID.trim()}`
      : null,
  };
}
