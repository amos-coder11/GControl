#!/usr/bin/env node
/**
 * Prueba local: verifica que el backend devuelve pedidos y montos.
 * Uso: npm run test:shopify
 */
import dotenv from "dotenv";

dotenv.config();

const BASE = process.env.TEST_BASE_URL || `http://127.0.0.1:${process.env.PORT || 3000}`;

async function get(path) {
  const res = await fetch(`${BASE}${path}`);
  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    throw new Error(`${path} -> JSON inválido (${res.status}): ${text.slice(0, 200)}`);
  }
  return { status: res.status, json };
}

function ok(label, passed) {
  console.log(`${passed ? "✅" : "❌"} ${label}`);
}

async function main() {
  console.log(`\n🔎 Prueba local Shopify → ${BASE}\n`);

  const health = await get("/health");
  ok("GET /health", health.status === 200 && health.json.ok === true);
  console.log("   shopify:", health.json.shopify);

  const summary = await get("/api/shopify/summary");
  ok("GET /api/shopify/summary", summary.status === 200 && summary.json.totalOrders > 0);
  if (summary.status === 200) {
    console.log("   total:", summary.json.totalOrders);
    console.log("   mes:", summary.json.monthOrderCount, "·", summary.json.monthRevenueFormatted);
    console.log("   source:", summary.json.source);
  } else {
    console.log("   error:", summary.json);
  }

  const orders = await get("/api/shopify/orders?limit=3");
  ok("GET /api/shopify/orders", orders.status === 200 && orders.json.orders?.length > 0);
  if (orders.status === 200) {
    for (const order of orders.json.orders) {
      console.log(`   · ${order.productTitle} — ${order.amountFormatted} — ${order.customerName}`);
    }
    console.log("   source:", orders.json.source);
  } else {
    console.log("   error:", orders.json);
  }

  const allPassed =
    health.status === 200 &&
    summary.status === 200 &&
    orders.status === 200 &&
    (orders.json.orders?.length || 0) > 0;

  console.log(allPassed ? "\n✅ Prueba local OK — la app puede cargar datos.\n" : "\n❌ Prueba fallida.\n");
  process.exit(allPassed ? 0 : 1);
}

main().catch((err) => {
  console.error("❌ Error:", err.message);
  console.error("   ¿Está el servidor corriendo? → npm run start");
  process.exit(1);
});
