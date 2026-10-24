'use strict';
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');

const app = express();
app.disable('x-powered-by');
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '32kb' }));

const PORT = Number(process.env.PORT || 8080);
const API_TOKEN = process.env.API_BEARER_TOKEN || '';
const ALLOW_DEMO_TOKEN = process.env.ALLOW_DEMO_TOKEN === 'true';
const SOS_WEBHOOK_URL = process.env.SOS_WEBHOOK_URL || '';

// Database adapter seam: replace these Maps with repository calls for your chosen database.
// Data is intentionally ephemeral; a restart clears it. This avoids pretending a DB exists.
const patients = new Map();
const eventStore = new Map();
const sosStore = new Map();
const now = () => new Date().toISOString();
const isFiniteNumber = n => typeof n === 'number' && Number.isFinite(n);
const pushBounded = (list, item, max = 100) => { list.unshift(item); if (list.length > max) list.length = max; };
function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (API_TOKEN && token === API_TOKEN) return next();
  if (ALLOW_DEMO_TOKEN && token === 'demo-token') return next();
  if (!API_TOKEN && !ALLOW_DEMO_TOKEN) return res.status(503).json({ error: 'auth_not_configured', message: 'Set API_BEARER_TOKEN before using the API.' });
  return res.status(401).json({ error: 'unauthorized' });
}
function patientRecord(id) {
  if (!patients.has(id)) patients.set(id, { patient_id: id, status: 'unknown', last_location: null, updated_at: null });
  return patients.get(id);
}
function recordEvent(patientId, type, detail, extra = {}) {
  const event = { id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`, patient_id: patientId, type, detail, created_at: now(), ...extra };
  if (!eventStore.has(patientId)) eventStore.set(patientId, []);
  pushBounded(eventStore.get(patientId), event);
  return event;
}
app.get('/health', (_req, res) => res.json({ ok: true, service: 'dishaflow-api', time: now(), persistence: 'in-memory; replace with database adapter' }));
app.use('/api', requireAuth);

app.post('/api/locations', (req, res) => {
  const { patient_id, latitude, longitude, accuracy_m, recorded_at } = req.body || {};
  if (typeof patient_id !== 'string' || !patient_id.trim() || !isFiniteNumber(latitude) || !isFiniteNumber(longitude) || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return res.status(400).json({ error: 'invalid_location', message: 'patient_id, valid latitude and longitude are required.' });
  }
  const location = { latitude, longitude, accuracy_m: isFiniteNumber(accuracy_m) ? accuracy_m : null, recorded_at: typeof recorded_at === 'string' ? recorded_at : now() };
  const patient = patientRecord(patient_id.trim()); patient.last_location = location; patient.status = 'online'; patient.updated_at = now();
  recordEvent(patient.patient_id, 'location', 'Location update received', { location });
  return res.status(202).json({ accepted: true, last_location: location });
});

app.post('/api/events', (req, res) => {
  const { patient_id, type, detail, created_at } = req.body || {};
  if (typeof patient_id !== 'string' || !patient_id.trim() || typeof type !== 'string' || !type.trim()) return res.status(400).json({ error: 'invalid_event' });
  const event = recordEvent(patient_id.trim(), type.trim().slice(0, 80), typeof detail === 'string' ? detail.slice(0, 1000) : '', { client_created_at: typeof created_at === 'string' ? created_at : null });
  patientRecord(patient_id.trim()).updated_at = now();
  return res.status(201).json({ accepted: true, event });
});

app.post('/api/sos', async (req, res) => {
  const { patient_id, message, latitude, longitude, created_at } = req.body || {};
  if (typeof patient_id !== 'string' || !patient_id.trim()) return res.status(400).json({ error: 'invalid_sos', message: 'patient_id is required.' });
  if ((latitude != null && !isFiniteNumber(latitude)) || (longitude != null && !isFiniteNumber(longitude))) return res.status(400).json({ error: 'invalid_coordinates' });
  const id = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const sos = { id, patient_id: patient_id.trim(), message: typeof message === 'string' ? message.slice(0, 1000) : 'Emergency assistance requested', latitude: isFiniteNumber(latitude) ? latitude : null, longitude: isFiniteNumber(longitude) ? longitude : null, created_at: typeof created_at === 'string' ? created_at : now(), accepted_at: now(), delivery_status: 'accepted_not_delivered' };
  if (!sosStore.has(sos.patient_id)) sosStore.set(sos.patient_id, []);
  pushBounded(sosStore.get(sos.patient_id), sos);
  recordEvent(sos.patient_id, 'sos', sos.message, { sos_id: id, latitude: sos.latitude, longitude: sos.longitude });
  patientRecord(sos.patient_id).updated_at = now();
  // Optional notification webhook. Configure it to call your FCM/SMS/provider integration.
  if (SOS_WEBHOOK_URL) {
    try {
      const response = await fetch(SOS_WEBHOOK_URL, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(sos), signal: AbortSignal.timeout(7000) });
      sos.delivery_status = response.ok ? 'webhook_accepted' : 'webhook_failed';
    } catch (_e) { sos.delivery_status = 'webhook_failed'; }
  }
  // A successful API response means the server accepted the SOS, not that a human received it.
  return res.status(202).json({ accepted: true, sos_id: id, delivery_status: sos.delivery_status, warning: 'Implement and verify caregiver notification delivery before relying on SOS.' });
});

app.get('/api/patients/:patientId/status', (req, res) => {
  const id = req.params.patientId;
  const patient = patientRecord(id);
  const alerts = (eventStore.get(id) || []).filter(e => ['sos', 'urgent', 'alert', 'obstacle'].includes(String(e.type).toLowerCase())).slice(0, 20);
  const soses = sosStore.get(id) || [];
  return res.json({ ...patient, recent_alerts: [...soses.map(s => ({ type: 'sos', created_at: s.accepted_at, message: s.message, delivery_status: s.delivery_status, latitude: s.latitude, longitude: s.longitude })), ...alerts].slice(0, 20) });
});

app.get('/api/patients/:patientId/events', (req, res) => {
  const limit = Math.max(1, Math.min(100, Number(req.query.limit || 50)));
  return res.json({ patient_id: req.params.patientId, events: (eventStore.get(req.params.patientId) || []).slice(0, limit) });
});

app.use((err, _req, res, _next) => { console.error('Unhandled API error:', err?.message || err); res.status(500).json({ error: 'internal_error' }); });
app.listen(PORT, () => console.log(`DishaFlow API listening on port ${PORT}; persistence is in-memory until a database adapter is connected.`));
