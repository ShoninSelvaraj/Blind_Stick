# BlindStick Companion API backend (database deliberately not included)

Requires Node.js 20+. This is an actual REST service, not just API documentation. It provides location ingestion, event ingestion, SOS acceptance, patient status and event history. Storage is in memory so the team can test integration immediately; data is lost when the process restarts. Replace the Map-backed functions with your chosen database repository before deployment.

## Run

```bash
cp .env.example .env
# Set API_BEARER_TOKEN to a long random value. ALLOW_DEMO_TOKEN=true is development-only.
npm install
API_BEARER_TOKEN='replace-with-long-random-secret' npm start
```

For local Android emulator use `http://10.0.2.2:8080` as the app base URL. For a physical phone, use the reachable LAN IP of the machine running this server or a deployed HTTPS URL. Android app network security is configured for HTTPS; don't ship plain HTTP in production.

## Auth note

The backend accepts a configured static bearer token, which is useful for wiring/testing but not a multi-user identity system. Implement real authentication, caregiver-patient pairing/authorization, token lifecycle, consent, audit logging, rate limits and abuse protection before production. Avoid a shared token across all users.

## SOS delivery

`POST /api/sos` stores/accepts the alert in memory and optionally POSTs it to `SOS_WEBHOOK_URL`. The webhook must be your actual notification dispatcher (for example, a server-side FCM/SMS provider integration). `accepted_not_delivered` means accepted by this API only. Do not claim an emergency message has reached a caregiver unless delivery is confirmed by the notification system.

## Database adapter

Replace `patients`, `eventStore`, and `sosStore` Map usage in `server.js` with a repository backed by the database you choose. The REST contract should remain stable. Use per-patient authorization checks before returning status/events and avoid retaining precise location longer than needed.
