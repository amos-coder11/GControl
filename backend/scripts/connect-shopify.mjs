#!/usr/bin/env node
/**
 * Conecta Gflow con Shopify: abre OAuth e intenta verificar la instalación.
 */
import { spawn } from "child_process";
import dotenv from "dotenv";

dotenv.config();

const BASE = `http://127.0.0.1:${process.env.PORT || 3000}`;

async function get(path) {
  const res = await fetch(`${BASE}${path}`);
  return { status: res.status, json: await res.json().catch(() => ({})) };
}

async function waitForServer(maxMs = 8000) {
  const start = Date.now();
  while (Date.now() - start < maxMs) {
    try {
      const res = await fetch(`${BASE}/health`);
      if (res.ok) return true;
    } catch {}
    await new Promise((r) => setTimeout(r, 400));
  }
  return false;
}

function openUrl(url) {
  const cmd = process.platform === "darwin" ? "open" : process.platform === "win32" ? "start" : "xdg-open";
  spawn(cmd, [url], { detached: true, stdio: "ignore" }).unref();
}

async function main() {
  console.log("\n🔗 Conectando Gflow → Shopify (drgsmileusa)\n");

  const up = await waitForServer();
  if (!up) {
    console.log("⚠️  Backend no responde. Inícialo con: npm run start");
    process.exit(1);
  }

  let status = await get("/api/shopify/status");
  if (status.json.install?.installed) {
    console.log("✅ Ya conectado a", status.json.install.shop);
    const summary = await get("/api/shopify/summary");
    console.log("   Pedidos:", summary.json.totalOrders, "· Mes:", summary.json.monthRevenueFormatted);
    console.log("   Fuente:", summary.json.source);
    process.exit(0);
  }

  const urls = await get("/api/shopify/install-url");
  if (urls.status !== 200) {
    console.error("❌ No se pudo generar URL de instalación:", urls.json);
    process.exit(1);
  }

  console.log("1. Abriendo instalación OAuth en el navegador…");
  console.log("   ", urls.json.authorizeUrl);
  openUrl(`${BASE}/api/shopify/connect`);

  console.log("\n2. Inicia sesión en drgsmileusa y pulsa Instalar / Aprobar.");
  console.log("   Página:", `${BASE}/api/shopify/connect`);
  console.log("   Redirect URI en Partners (si pide):", urls.json.redirectUri);
  console.log("\n3. Esperando conexión (máx. 2 min)…\n");

  for (let i = 0; i < 24; i++) {
    await new Promise((r) => setTimeout(r, 5000));
    status = await get("/api/shopify/status");
    if (status.json.install?.installed) {
      const summary = await get("/api/shopify/summary");
      console.log("✅ Conectado a Shopify:", status.json.install.shop);
      console.log("   Pedidos:", summary.json.totalOrders, "· Mes:", summary.json.monthRevenueFormatted);
      console.log("   Fuente:", summary.json.source, "\n");
      process.exit(0);
    }
    process.stdout.write(".");
  }

  console.log("\n\n⏳ Instalación pendiente. Abre manualmente:");
  console.log(`   ${BASE}/api/shopify/install`);
  process.exit(1);
}

main().catch((err) => {
  console.error("❌", err.message);
  process.exit(1);
});
