/**
 * Express server: POST /session proxies OpenAI Realtime session creation.
 * Never exposes OPENAI_API_KEY to clients.
 */
import cors from "cors";
import dotenv from "dotenv";
import express from "express";

dotenv.config();

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const PORT = Number(process.env.PORT) || 3000;
const NODE_ENV = process.env.NODE_ENV || "development";

const OPENAI_SESSIONS_URL = "https://api.openai.com/v1/realtime/sessions";

const SESSION_BODY = {
  model: "gpt-4o-realtime-preview",
  voice: "alloy",
  instructions: "You are a helpful voice assistant.",
  modalities: ["audio", "text"],
};

function logRequest(req, res, start, status) {
  const ts = new Date().toISOString();
  console.info(
    `[${ts}] ${req.method} ${req.path} -> ${status} (${Date.now() - start}ms)`
  );
}

const app = express();
app.use(express.json({ limit: "1mb" }));

app.use(
  cors({
    origin: true,
    methods: ["GET", "POST", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Accept"],
  })
);

app.get("/health", (req, res) => {
  res.status(200).json({ ok: true });
});

app.post("/session", async (req, res) => {
  const start = Date.now();

  if (!OPENAI_API_KEY || OPENAI_API_KEY.trim() === "") {
    logRequest(req, res, start, 500);
    return res.status(500).json({
      error: "server_misconfigured",
      message: "OPENAI_API_KEY is not set on the server.",
    });
  }

  try {
    const upstream = await fetch(OPENAI_SESSIONS_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(SESSION_BODY),
    });

    const text = await upstream.text();
    let json;
    try {
      json = text ? JSON.parse(text) : {};
    } catch {
      logRequest(req, res, start, upstream.status);
      return res.status(502).json({
        error: "upstream_invalid_json",
        message: "OpenAI returned non-JSON body.",
      });
    }

    logRequest(req, res, start, upstream.status);
    return res.status(upstream.status).json(json);
  } catch (err) {
    logRequest(req, res, start, 502);
    console.error("[session] fetch error:", err);
    return res.status(502).json({
      error: "upstream_unreachable",
      message: "Could not reach OpenAI API.",
    });
  }
});

app.listen(PORT, () => {
  console.info(
    `[voiceapp-backend] listening on :${PORT} (NODE_ENV=${NODE_ENV})`
  );
});
