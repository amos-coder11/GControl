import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { getInstalledAccessToken } from "./shopify-auth.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
/**
 * Shopify Admin API client (client credentials).
 * Secrets stay server-side; iOS only calls this backend.
 */

const API_VERSION = process.env.SHOPIFY_API_VERSION || "2025-01";
const NODE_ENV = process.env.NODE_ENV || "development";
const SESSION_PATH = path.join(__dirname, "..", ".shopify-session.json");

let cachedToken = null;
let tokenExpiresAt = 0;

function readSessionToken() {
  try {
    const raw = fs.readFileSync(SESSION_PATH, "utf8");
    const json = JSON.parse(raw);
    return json?.accessToken?.trim() || null;
  } catch {
    return null;
  }
}

function shopDomain() {
  const raw = (process.env.SHOPIFY_SHOP || "").trim().toLowerCase();
  if (!raw) return null;
  return raw.endsWith(".myshopify.com") ? raw : `${raw}.myshopify.com`;
}

function adminAccessToken() {
  return (
    getInstalledAccessToken() ||
    (process.env.SHOPIFY_ADMIN_ACCESS_TOKEN || "").trim() ||
    readSessionToken() ||
    null
  );
}

function useDevFixture() {
  if (adminAccessToken()) return false;
  return (
    NODE_ENV === "development" &&
    ["1", "true", "yes"].includes(
      String(process.env.SHOPIFY_DEV_FIXTURE || "").toLowerCase()
    )
  );
}

function isConfigured() {
  return Boolean(
    shopDomain() &&
      (adminAccessToken() ||
        (process.env.SHOPIFY_CLIENT_ID?.trim() &&
          process.env.SHOPIFY_CLIENT_SECRET?.trim()))
  );
}

async function getAccessToken() {
  const directToken = adminAccessToken();
  if (directToken) return directToken;

  if (!shopDomain() || !process.env.SHOPIFY_CLIENT_ID?.trim() || !process.env.SHOPIFY_CLIENT_SECRET?.trim()) {
    throw new Error("shopify_not_configured");
  }

  const now = Date.now();
  if (cachedToken && now < tokenExpiresAt - 60_000) {
    return cachedToken;
  }

  const shop = shopDomain();
  const body = new URLSearchParams({
    grant_type: "client_credentials",
    client_id: process.env.SHOPIFY_CLIENT_ID.trim(),
    client_secret: process.env.SHOPIFY_CLIENT_SECRET.trim(),
  });

  const res = await fetch(`https://${shop}/admin/oauth/access_token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });

  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    const htmlError = text.match(/Oauth error ([a-z_]+)/i)?.[1];
    throw new Error(
      htmlError
        ? `shopify_token_failed:${res.status}:${htmlError}`
        : `shopify_token_invalid_json:${text.slice(0, 200)}`
    );
  }

  if (!res.ok) {
    const detail = json.error_description || json.error || text.slice(0, 200);
    throw new Error(`shopify_token_failed:${res.status}:${detail}`);
  }

  cachedToken = json.access_token;
  const ttl = Number(json.expires_in) || 86_399;
  tokenExpiresAt = now + ttl * 1000;
  return cachedToken;
}

async function shopifyAdminGet(path, query = {}) {
  const token = await getAccessToken();
  const shop = shopDomain();
  const url = new URL(`https://${shop}/admin/api/${API_VERSION}${path}`);
  for (const [key, value] of Object.entries(query)) {
    if (value !== undefined && value !== null && value !== "") {
      url.searchParams.set(key, String(value));
    }
  }

  const res = await fetch(url, {
    headers: {
      "X-Shopify-Access-Token": token,
      Accept: "application/json",
    },
  });

  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`shopify_invalid_json:${path}`);
  }

  if (!res.ok) {
    const detail = json.errors || json.error || text.slice(0, 200);
    throw new Error(`shopify_api_failed:${res.status}:${JSON.stringify(detail)}`);
  }

  return json;
}

function mapFinancialStatus(status) {
  switch (status) {
    case "paid":
    case "partially_paid":
      return "completed";
    case "pending":
    case "authorized":
    case "partially_refunded":
      return "processing";
    default:
      return "pending";
  }
}

function mapAppStatus(financialStatus, fulfillmentStatus) {
  if (financialStatus === "refunded" || financialStatus === "voided") {
    return "pending";
  }
  if (fulfillmentStatus === "fulfilled") {
    return "completed";
  }
  return mapFinancialStatus(financialStatus);
}

function formatTimeLabel(isoDate) {
  const date = new Date(isoDate);
  if (Number.isNaN(date.getTime())) return "—";

  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startOfYesterday = new Date(startOfToday);
  startOfYesterday.setDate(startOfYesterday.getDate() - 1);

  const time = date.toLocaleTimeString("es-ES", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });

  if (date >= startOfToday) return `Hoy, ${time}`;
  if (date >= startOfYesterday) return "Ayer";
  return date.toLocaleDateString("es-ES", { day: "2-digit", month: "short" });
}

function customerLabel(order) {
  const customer = order.customer;
  if (customer) {
    const name = [customer.first_name, customer.last_name].filter(Boolean).join(" ").trim();
    if (name) return name;
    if (customer.email) return customer.email.split("@")[0];
  }
  if (order.email) return order.email.split("@")[0];
  if (order.billing_address?.name) return order.billing_address.name;
  return "Cliente Shopify";
}

function channelLabel(order) {
  const source = (order.source_name || "").toLowerCase();
  if (source.includes("tiktok")) return "TikTok Shop";
  if (source.includes("instagram")) return "Instagram";
  if (source.includes("facebook")) return "Facebook";
  if (source.includes("pos")) return "En vivo";
  if (order.tags) {
    const tags = order.tags.toLowerCase();
    if (tags.includes("tiktok")) return "TikTok Shop";
    if (tags.includes("instagram")) return "Instagram";
    if (tags.includes("facebook")) return "Facebook";
    if (tags.includes("live") || tags.includes("vivo")) return "En vivo";
  }
  return "Shopify";
}

function productsLabel(lineItems) {
  const count = lineItems.length;
  if (count <= 1) {
    const brand = lineItems[0]?.vendor || "drgsmileusa";
    return `1 producto · ${brand}`;
  }
  const names = lineItems.map((item) => item.title).join(" · ");
  return `${count} productos · ${names}`;
}

function mapOrder(order) {
  const lineItems = order.line_items || [];
  const firstItem = lineItems[0];
  const amount = Number(order.total_price || order.current_total_price || 0);

  return {
    id: `shopify-${order.id}`,
    shopifyId: order.id,
    orderNumber: order.name,
    customerName: customerLabel(order),
    productTitle: firstItem?.title || order.name || "Pedido Shopify",
    productsLabel: productsLabel(lineItems),
    imageURL: null,
    amount,
    amountFormatted: formatUSD(amount),
    currency: order.currency || "USD",
    timeLabel: formatTimeLabel(order.created_at),
    status: mapAppStatus(order.financial_status, order.fulfillment_status),
    channel: channelLabel(order),
    createdAt: order.created_at,
    lineItems: lineItems.map((item) => ({
      id: String(item.id),
      name: item.title,
      quantity: item.quantity,
      unitPrice: Number(item.price || 0),
      imageURL: null,
    })),
  };
}

function formatUSD(value) {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits: 2,
  }).format(value);
}

function monthBounds(date = new Date()) {
  const start = new Date(date.getFullYear(), date.getMonth(), 1);
  const end = new Date(date.getFullYear(), date.getMonth() + 1, 0, 23, 59, 59, 999);
  return { start, end };
}

function isInMonth(isoDate, date = new Date()) {
  const created = new Date(isoDate);
  const { start, end } = monthBounds(date);
  return created >= start && created <= end;
}

function fixtureRawOrders() {
  const now = new Date();
  const hoursAgo = (h) => new Date(now.getTime() - h * 60 * 60 * 1000).toISOString();
  const daysAgo = (d, hour = 12) =>
    new Date(now.getFullYear(), now.getMonth(), now.getDate() - d, hour, 30).toISOString();

  return [
    {
      id: 5001,
      name: "#5001",
      email: "jorgedelgado_9@example.com",
      total_price: "116.00",
      currency: "USD",
      financial_status: "paid",
      fulfillment_status: "partial",
      source_name: "tiktok",
      tags: "tiktok, affiliate",
      created_at: hoursAgo(2),
      customer: { first_name: "Jorge", last_name: "Delgado", email: "jorgedelgado_9@example.com" },
      line_items: [
        { id: 1, title: "NAD +", quantity: 1, price: "49.00", vendor: "drgsmileusa" },
        { id: 2, title: "Traders Market Energy Focus", quantity: 1, price: "67.00", vendor: "drgsmileusa" },
      ],
    },
    {
      id: 5002,
      name: "#5002",
      email: "camivillalba@example.com",
      total_price: "67.00",
      currency: "USD",
      financial_status: "paid",
      fulfillment_status: "fulfilled",
      source_name: "instagram",
      tags: "instagram",
      created_at: daysAgo(1, 18),
      customer: { first_name: "Cami", last_name: "Villalba", email: "camivillalba@example.com" },
      line_items: [
        { id: 3, title: "Traders Recovery Sleep & Wellness", quantity: 1, price: "67.00", vendor: "drgsmileusa" },
      ],
    },
    {
      id: 5003,
      name: "#5003",
      email: "raquelonodri@example.com",
      total_price: "132.40",
      currency: "USD",
      financial_status: "pending",
      fulfillment_status: null,
      source_name: "facebook",
      tags: "facebook, bundle",
      created_at: hoursAgo(5),
      customer: { first_name: "Raquel", last_name: "Onodri", email: "raquelonodri@example.com" },
      line_items: [
        { id: 4, title: "NAD +", quantity: 1, price: "49.00", vendor: "drgsmileusa" },
        { id: 5, title: "Traders Market Energy Focus", quantity: 1, price: "67.00", vendor: "drgsmileusa" },
        { id: 6, title: "Traders Recovery Sleep & Wellness", quantity: 1, price: "67.00", vendor: "drgsmileusa" },
      ],
    },
    {
      id: 5004,
      name: "#5004",
      email: "mariagomez@example.com",
      total_price: "49.00",
      currency: "USD",
      financial_status: "paid",
      fulfillment_status: "fulfilled",
      source_name: "pos",
      tags: "live, en-vivo",
      created_at: hoursAgo(8),
      customer: { first_name: "Maria", last_name: "Gomez", email: "mariagomez@example.com" },
      line_items: [{ id: 7, title: "NAD +", quantity: 1, price: "49.00", vendor: "drgsmileusa" }],
    },
    {
      id: 5005,
      name: "#5005",
      email: "carlosfit23@example.com",
      total_price: "67.00",
      currency: "USD",
      financial_status: "authorized",
      fulfillment_status: null,
      source_name: "tiktok",
      tags: "tiktok",
      created_at: daysAgo(1, 10),
      customer: { first_name: "Carlos", last_name: "Fit", email: "carlosfit23@example.com" },
      line_items: [
        { id: 8, title: "Traders Market Energy Focus", quantity: 1, price: "67.00", vendor: "drgsmileusa" },
      ],
    },
  ];
}

function fetchFixtureOrders(limit = 50) {
  const orders = fixtureRawOrders()
    .slice(0, limit)
    .map(mapOrder);
  return { orders, source: "shopify_fixture" };
}

function shouldUseFixture(err) {
  if (!useDevFixture()) return false;
  const message = err instanceof Error ? err.message : String(err);
  return (
    message.includes("app_not_installed") ||
    message.includes("shopify_not_configured") ||
    message.includes("shopify_token_failed")
  );
}

async function fetchLiveOrders({ limit = 50, status = "any" } = {}) {
  const json = await shopifyAdminGet("/orders.json", {
    status,
    limit: Math.min(Math.max(limit, 1), 250),
    order: "created_at desc",
  });

  const orders = (json.orders || []).map(mapOrder);
  return { orders, source: adminAccessToken() ? "shopify_admin_token" : "shopify" };
}

export async function fetchShopifyOrders({ limit = 50, status = "any" } = {}) {
  try {
    return await fetchLiveOrders({ limit, status });
  } catch (err) {
    if (shouldUseFixture(err)) {
      console.warn("[shopify] usando fixture local:", err.message);
      return fetchFixtureOrders(limit);
    }
    throw err;
  }
}

export async function fetchShopifySummary() {
  try {
    const { orders, source } = await fetchShopifyOrders({ limit: 250, status: "any" });
    const now = new Date();
    const monthOrders = orders.filter((o) => isInMonth(o.createdAt, now));
    const monthRevenue = monthOrders.reduce((sum, o) => sum + o.amount, 0);
    const pending = orders.filter((o) => o.status === "pending").length;
    const completed = orders.filter((o) => o.status === "completed").length;

    return {
      totalOrders: orders.length,
      pendingOrders: pending,
      completedOrders: completed,
      monthOrderCount: monthOrders.length,
      monthRevenue,
      monthRevenueFormatted: formatUSD(monthRevenue),
      source,
    };
  } catch (err) {
    if (shouldUseFixture(err)) {
      const { orders, source } = fetchFixtureOrders(250);
      const now = new Date();
      const monthOrders = orders.filter((o) => isInMonth(o.createdAt, now));
      const monthRevenue = monthOrders.reduce((sum, o) => sum + o.amount, 0);
      return {
        totalOrders: orders.length,
        pendingOrders: orders.filter((o) => o.status === "pending").length,
        completedOrders: orders.filter((o) => o.status === "completed").length,
        monthOrderCount: monthOrders.length,
        monthRevenue,
        monthRevenueFormatted: formatUSD(monthRevenue),
        source,
      };
    }
    throw err;
  }
}

export function shopifyHealth() {
  const token = adminAccessToken();
  return {
    configured: isConfigured(),
    installed: Boolean(token),
    shop: shopDomain(),
    apiVersion: API_VERSION,
    authMode: token
      ? "oauth_access_token"
      : process.env.SHOPIFY_CLIENT_ID
        ? "client_credentials"
        : "none",
    devFixture: useDevFixture(),
  };
}
