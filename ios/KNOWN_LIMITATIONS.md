# VoiceApp — known limitations and TODOs

This document lists unverified assumptions and explicit `// TODO: VERIFY` items from the OpenAI Realtime + WebRTC implementation.

## OpenAI API

- **Ephemeral token lifetime**: Documented as ~60 seconds. Client validates `expires_at` against local time (clock skew may cause false negatives).
- **`expires_at` units**: Assumed Unix **seconds**. // TODO: VERIFY — confirm unit in current `client_secret` payload.
- **SDP exchange**: Assumed **HTTP 201** with body = raw SDP answer string. // TODO: VERIFY — whether any redirects or alternate success codes appear in practice.
- **Event type names**: Parser accepts `response.audio.delta` and `response.output_audio.delta` as possible audio delta events. // TODO: VERIFY — exact `type` strings for your model version.
- **`response.audio_transcript.delta` payload**: Assumes optional top-level `delta` string. // TODO: VERIFY — nested or renamed fields in newer schemas.
- **`session.update` before first response** in WebRTC mode: not sent by default. // TODO: VERIFY — whether pre-configuration changes session behavior.

## WebRTC (stasel / Google stack)

- **ICE gathering vs SDP POST**: After `setLocalDescription`, the client waits **~400 ms** before reading the local SDP, then POSTs. // TODO: VERIFY — whether OpenAI requires trickle-complete or full ICE in the initial offer.
- **Remote audio playback**: Mic is sent via local audio track; remote TTS is expected on the inbound audio track. // TODO: VERIFY — whether iOS routes remote WebRTC audio to speaker automatically or requires `RTCAudioSession` / `AVAudioSession` tweaks.
- **Data channel direction**: Created locally with label `oai-events` before the offer. // TODO: VERIFY — OpenAI expectation for DTLS/SCTP negotiation order.

## iOS runtime

- **Simulator**: Microphone and WebRTC behavior may differ from device; always validate on hardware for production.
- **ATS**: `NSAllowsLocalNetworking` is enabled for dev backends; production should use HTTPS and tighten ATS.

## Backend

- **Session proxy**: Returns upstream JSON verbatim; if OpenAI changes shape, update `SessionResponse` decoding accordingly.

## Security reminder

- Never commit OpenAI API keys. Rotate any key that was pasted into chat, logs, or tickets.
