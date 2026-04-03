/**
 * Envía push APNs cuando se inserta un mensaje en `team_direct_messages` o `team_group_messages`,
 * o una tarea en `team_coordinator_tasks` (Viera → comercial).
 *
 * Configuración en Supabase Dashboard:
 * 1. Secrets: APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (PEM completo de la clave .p8),
 *    APNS_BUNDLE_ID (ej. com.carhub.app), PUSH_WEBHOOK_SECRET,
 *    opcional APNS_USE_SANDBOX=true para builds de desarrollo.
 * 2. Database Webhooks: dos disparadores INSERT → URL de esta función,
 *    cabecera `x-push-secret: <PUSH_WEBHOOK_SECRET>`.
 * 3. Deploy: supabase functions deploy send-message-push --no-verify-jwt
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { SignJWT, importPKCS8 } from "npm:jose@5.9.6";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-push-secret",
};

type DmRecord = {
  id: string;
  sender_id: string;
  recipient_id: string;
  body: string;
};

type GroupRecord = {
  id: string;
  sender_id: string;
  body: string;
};

type CoordinatorTaskRecord = {
  id: string;
  sender_id: string;
  recipient_id: string;
  title: string;
  body: string;
  deadline_at: string;
};

/** Texto bajo «Horario e instrucciones de entrega o recogida:» en tareas Viera (cuerpo largo en BD). */
function extractHorarioFromVieraTaskBody(body: string): string {
  const marker = "Horario e instrucciones de entrega o recogida:";
  const idx = body.indexOf(marker);
  if (idx < 0) return "";
  let rest = body.slice(idx + marker.length).trim();
  const parts = rest.split(/\n\n/);
  const first = (parts[0] ?? "").trim();
  return first.replace(/\s+/g, " ").trim();
}

function formatTaskDeadlineEs(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return new Intl.DateTimeFormat("es-ES", {
    weekday: "short",
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(d);
}

function truncate(s: string, max: number): string {
  const t = s.trim();
  if (t.length <= max) return t;
  return t.slice(0, max - 1) + "…";
}

const TEAM_DIRECT_VOICE_PREFIX = "CARHUB_VOICE_V1:";

function dmPushBodyPreview(body: string): string {
  if (body.startsWith(TEAM_DIRECT_VOICE_PREFIX)) return "Nota de voz";
  return body;
}

/** PEM PKCS#8 del .p8 de Apple: cabeceras + saltos de línea. El panel de Supabase suele guardar \n como texto "\\n". */
function normalizeApnsPrivateKeyPem(raw: string): string {
  let pem = raw.trim().replace(/\r\n/g, "\n");
  pem = pem.replace(/\\n/g, "\n");
  if (!pem.includes("BEGIN PRIVATE KEY") || !pem.includes("END PRIVATE KEY")) {
    throw new Error(
      "APNS_PRIVATE_KEY: pega el archivo .p8 completo, con -----BEGIN PRIVATE KEY----- y -----END PRIVATE KEY-----",
    );
  }
  return pem;
}

async function apnsJwt(): Promise<string> {
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const raw = Deno.env.get("APNS_PRIVATE_KEY");
  if (!keyId || !teamId || !raw) {
    throw new Error("Faltan APNS_KEY_ID, APNS_TEAM_ID o APNS_PRIVATE_KEY");
  }
  const pem = normalizeApnsPrivateKeyPem(raw);
  let key: CryptoKey;
  try {
    key = await importPKCS8(pem, "ES256");
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    throw new Error(
      `APNS_PRIVATE_KEY no es un PEM PKCS#8 válido (${msg}). Copia el .p8 tal cual desde Apple (Auth Key), sin comillas extra ni solo la parte base64.`,
    );
  }
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt()
    .setExpirationTime("50m")
    .sign(key);
}

/** APNs penaliza si firmas un JWT nuevo en cada POST (429 TooManyProviderTokenUpdates). Reutilizar ~40 min. */
let providerJwtCache: { token: string; expiresAtMs: number } | null = null;

async function getApnsProviderJwt(): Promise<string> {
  const now = Date.now();
  if (providerJwtCache && providerJwtCache.expiresAtMs > now + 60_000) {
    return providerJwtCache.token;
  }
  const token = await apnsJwt();
  providerJwtCache = { token, expiresAtMs: now + 40 * 60 * 1000 };
  return token;
}

async function sendApnsAlert(
  deviceTokenHex: string,
  payload: Record<string, unknown>,
  providerJwt: string,
): Promise<{ ok: boolean; status: number; body: string }> {
  const bundleId = Deno.env.get("APNS_BUNDLE_ID");
  if (!bundleId) throw new Error("Falta APNS_BUNDLE_ID");
  const sandbox = Deno.env.get("APNS_USE_SANDBOX") === "true";
  const host = sandbox
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
  const url = `${host}/3/device/${deviceTokenHex}`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `bearer ${providerJwt}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": "0",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  const text = await res.text();
  if (!res.ok) {
    console.error("[send-message-push] APNs rechazó el envío", {
      status: res.status,
      body: text.slice(0, 500),
      tokenPrefix: deviceTokenHex.slice(0, 8),
      sandbox,
    });
  }
  return { ok: res.ok, status: res.status, body: text };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const webhookSecret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (webhookSecret && req.headers.get("x-push-secret") !== webhookSecret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceKey);

  let body: {
    type?: string;
    eventType?: string;
    table?: string;
    record?: Record<string, unknown>;
  };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "JSON inválido" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const table = body.table;
  const record = body.record;
  const insertEvent =
    body.type === "INSERT" ||
    body.type === "insert" ||
    body.eventType === "INSERT" ||
    body.eventType === "insert";
  if (!table || !record || !insertEvent) {
    return new Response(JSON.stringify({ ok: true, skipped: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    if (table === "team_direct_messages") {
      const r = record as unknown as DmRecord;
      const senderId = r.sender_id;
      const recipientId = r.recipient_id;
      const text = truncate(dmPushBodyPreview(r.body), 180);

      const profilesTable = Deno.env.get("PROFILES_TABLE") ?? "user_profiles";
      const { data: profile } = await supabase
        .from(profilesTable)
        .select("full_name, avatar_url")
        .eq("user_id", senderId)
        .maybeSingle();

      const senderName = (profile?.full_name as string | null)?.trim() ||
        "Usuario";
      const avatarUrl = (profile?.avatar_url as string | null) || null;

      const { data: dmRecipientPrefs } = await supabase
        .from(profilesTable)
        .select("notify_team_push")
        .eq("user_id", recipientId)
        .maybeSingle();

      if (dmRecipientPrefs?.notify_team_push === false) {
        return new Response(
          JSON.stringify({
            ok: true,
            skipped: true,
            table,
            reason: "recipient_disabled_team_push",
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const { data: devices, error: devErr } = await supabase
        .from("user_apns_devices")
        .select("device_token")
        .eq("user_id", recipientId);

      if (devErr) throw devErr;
      const tokens = (devices ?? []).map((d) => d.device_token as string);
      const sandbox = Deno.env.get("APNS_USE_SANDBOX") === "true";
      const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "";
      console.log("[send-message-push] DM", {
        recipientId,
        deviceCount: tokens.length,
        apnsSandbox: sandbox,
        bundleId,
        hint:
          tokens.length === 0
            ? "No hay filas en user_apns_devices para el destinatario (iPhone real + abrir sesión tras conceder permiso)."
            : sandbox
            ? "Token development/sandbox: APNS_USE_SANDBOX debe ser true."
            : "Build Release/TestFlight suele usar token production: APNS_USE_SANDBOX false.",
      });
      const apnsPayload = {
        aps: {
          alert: { title: senderName, body: text },
          sound: "default",
          "mutable-content": 1,
        },
        carhub: {
          kind: "dm",
          sender_id: senderId,
          avatar_url: avatarUrl,
        },
      };

      const providerJwt = await getApnsProviderJwt();
      const results = [];
      for (const hex of tokens) {
        const out = await sendApnsAlert(hex, apnsPayload, providerJwt);
        if (out.status === 410) {
          await supabase
            .from("user_apns_devices")
            .delete()
            .eq("user_id", recipientId)
            .eq("device_token", hex);
          console.log("[send-message-push] Token 410 Unregistered eliminado de user_apns_devices", {
            userId: recipientId,
            tokenPrefix: hex.slice(0, 8),
          });
        }
        results.push({ token: hex.slice(0, 8) + "…", ...out });
      }
      if (tokens.length > 0) {
        console.log("[send-message-push] DM APNs", {
          results: results.map((r) => ({
            token: r.token,
            ok: r.ok,
            status: r.status,
          })),
        });
      }

      return new Response(JSON.stringify({ ok: true, table, results }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (table === "team_group_messages") {
      const r = record as unknown as GroupRecord;
      const senderId = r.sender_id;
      const text = truncate(r.body, 180);

      const profilesTable = Deno.env.get("PROFILES_TABLE") ?? "user_profiles";
      const { data: profile } = await supabase
        .from(profilesTable)
        .select("full_name, avatar_url")
        .eq("user_id", senderId)
        .maybeSingle();

      const senderName = (profile?.full_name as string | null)?.trim() ||
        "Usuario";
      const avatarUrl = (profile?.avatar_url as string | null) || null;

      const { data: devices, error: devErr } = await supabase
        .from("user_apns_devices")
        .select("device_token, user_id")
        .neq("user_id", senderId);

      if (devErr) throw devErr;

      const uniqueRecipientIds = [
        ...new Set((devices ?? []).map((d) => d.user_id as string)),
      ];
      const allowGroupPush = new Map<string, boolean>();
      for (const uid of uniqueRecipientIds) allowGroupPush.set(uid, true);
      if (uniqueRecipientIds.length > 0) {
        const { data: groupPrefs } = await supabase
          .from(profilesTable)
          .select("user_id, notify_team_push")
          .in("user_id", uniqueRecipientIds);
        for (const row of groupPrefs ?? []) {
          const uid = row.user_id as string;
          if (row.notify_team_push === false) allowGroupPush.set(uid, false);
        }
      }

      const apnsPayload = {
        aps: {
          alert: {
            title: "Mi equipo · grupo",
            subtitle: senderName,
            body: text,
          },
          sound: "default",
          "mutable-content": 1,
        },
        carhub: {
          kind: "group",
          sender_id: senderId,
          avatar_url: avatarUrl,
        },
      };

      const providerJwt = await getApnsProviderJwt();
      const results = [];
      for (const row of devices ?? []) {
        const hex = row.device_token as string;
        const uid = row.user_id as string;
        if (allowGroupPush.get(uid) === false) continue;
        const out = await sendApnsAlert(hex, apnsPayload, providerJwt);
        if (out.status === 410) {
          await supabase
            .from("user_apns_devices")
            .delete()
            .eq("user_id", uid)
            .eq("device_token", hex);
        }
        results.push({ token: hex.slice(0, 8) + "…", ...out });
      }

      return new Response(JSON.stringify({ ok: true, table, results }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (table === "team_coordinator_tasks") {
      const r = record as unknown as CoordinatorTaskRecord;
      const recipientId = r.recipient_id;
      const senderId = r.sender_id;
      const taskId = r.id;
      const rawTitle = String(r.title ?? "");
      const rawBody = String(r.body ?? "");
      const vehicleSubtitle = truncate(rawTitle, 100);
      const horario = extractHorarioFromVieraTaskBody(rawBody);
      const horarioT = truncate(horario, 220);
      const plazoFmt = formatTaskDeadlineEs(String(r.deadline_at ?? ""));
      const bodyLines: string[] = [];
      if (horarioT.length > 0) {
        bodyLines.push(horarioT);
      } else {
        const fb = truncate(rawBody.replace(/\s+/g, " "), 240);
        if (fb.length > 0) bodyLines.push(fb);
      }
      if (plazoFmt.length > 0) {
        bodyLines.push(`Plazo: ${plazoFmt}`);
      }
      let alertBody = bodyLines.length > 0
        ? bodyLines.join("\n")
        : truncate(rawBody.replace(/\s+/g, " "), 200);
      if (!alertBody.trim()) {
        alertBody = plazoFmt.length > 0 ? `Plazo: ${plazoFmt}` : "Nueva tarea de Viera";
      }
      const taskNotesForClient = rawBody.length > 3500
        ? rawBody.slice(0, 3497) + "…"
        : rawBody;

      const profilesTable = Deno.env.get("PROFILES_TABLE") ?? "user_profiles";
      const { data: recipientPrefs } = await supabase
        .from(profilesTable)
        .select("notify_team_push")
        .eq("user_id", recipientId)
        .maybeSingle();

      if (recipientPrefs?.notify_team_push === false) {
        return new Response(
          JSON.stringify({
            ok: true,
            skipped: true,
            table,
            reason: "recipient_disabled_team_push",
          }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const { data: profile } = await supabase
        .from(profilesTable)
        .select("full_name, avatar_url")
        .eq("user_id", senderId)
        .maybeSingle();

      const senderName = (profile?.full_name as string | null)?.trim() ||
        "Usuario";
      const avatarUrl = (profile?.avatar_url as string | null) || null;

      const { data: devices, error: taskDevErr } = await supabase
        .from("user_apns_devices")
        .select("device_token")
        .eq("user_id", recipientId);

      if (taskDevErr) throw taskDevErr;
      const tokens = (devices ?? []).map((d) => d.device_token as string);
      const sandbox = Deno.env.get("APNS_USE_SANDBOX") === "true";
      const bundleId = Deno.env.get("APNS_BUNDLE_ID") ?? "";
      console.log("[send-message-push] coordinator_task", {
        recipientId,
        taskId,
        deviceCount: tokens.length,
        apnsSandbox: sandbox,
        bundleId,
      });

      const apnsPayload = {
        aps: {
          alert: {
            title: senderName,
            subtitle: vehicleSubtitle.length > 0 ? vehicleSubtitle : undefined,
            body: alertBody,
          },
          category: "COORDINATOR_TASK",
          sound: "default",
          "mutable-content": 1,
        },
        carhub: {
          kind: "coordinator_task",
          task_id: taskId,
          sender_id: senderId,
          avatar_url: avatarUrl,
          deadline_at: r.deadline_at,
          task_title: rawTitle.length > 500 ? rawTitle.slice(0, 497) + "…" : rawTitle,
          task_notes: taskNotesForClient,
        },
      };

      const providerJwt = await getApnsProviderJwt();
      const taskResults = [];
      for (const hex of tokens) {
        const out = await sendApnsAlert(hex, apnsPayload, providerJwt);
        if (out.status === 410) {
          await supabase
            .from("user_apns_devices")
            .delete()
            .eq("user_id", recipientId)
            .eq("device_token", hex);
        }
        taskResults.push({ token: hex.slice(0, 8) + "…", ...out });
      }

      return new Response(
        JSON.stringify({ ok: true, table, results: taskResults }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(JSON.stringify({ ok: true, skipped: true, table }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("send-message-push", msg);
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
