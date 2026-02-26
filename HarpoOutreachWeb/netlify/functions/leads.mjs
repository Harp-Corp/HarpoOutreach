// Netlify Function: GET /api/leads, POST /api/leads
// In-memory store (resets on cold start) - replace with Sheets/DB for persistence
const leads = [];
let nextId = 1;
export default async (req) => {
  const cors = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' };
  if (req.method === 'OPTIONS') return new Response('', { status: 204, headers: { ...cors, 'Access-Control-Allow-Methods': 'GET,POST,OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type' } });
  if (req.method === 'GET') {
    return new Response(JSON.stringify(leads), { status: 200, headers: cors });
  }
  if (req.method === 'POST') {
    let body;
    try { body = await req.json(); } catch { return new Response('Bad Request', { status: 400 }); }
    const lead = { id: String(nextId++), status: 'new', createdAt: new Date().toISOString(), ...body };
    leads.push(lead);
    return new Response(JSON.stringify(lead), { status: 201, headers: cors });
  }
  return new Response('Method Not Allowed', { status: 405 });
};
export const config = { path: '/api/leads' };
