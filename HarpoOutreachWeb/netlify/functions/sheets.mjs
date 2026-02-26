// Netlify Function: GET /api/sheets/leads, POST /api/sheets/init
// Google Sheets integration using service account or OAuth token stored in env

const SHEET_ID = process.env.GOOGLE_SHEET_ID;
const cors = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' };

async function getAccessToken() {
  // Use refresh token flow with stored credentials
  const tokenUrl = 'https://oauth2.googleapis.com/token';
  const params = new URLSearchParams({
    client_id: process.env.GOOGLE_CLIENT_ID,
    client_secret: process.env.GOOGLE_CLIENT_SECRET,
    refresh_token: process.env.GOOGLE_REFRESH_TOKEN,
    grant_type: 'refresh_token'
  });
  const resp = await fetch(tokenUrl, { method: 'POST', body: params });
  const data = await resp.json();
  return data.access_token;
}

async function readLeads(spreadsheetId, accessToken) {
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${spreadsheetId}/values/Leads!A:Z`;
  const resp = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
  const data = await resp.json();
  if (!data.values || data.values.length < 2) return [];
  const [headers, ...rows] = data.values;
  return rows.map(row => {
    const obj = {};
    headers.forEach((h, i) => { obj[h] = row[i] || ''; });
    return obj;
  });
}

async function initSheet(spreadsheetId, accessToken) {
  const headers = [['ID','Company','Industry','Region','Contact','Email','Status','CreatedAt','Notes']];
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${spreadsheetId}/values/Leads!A1:I1?valueInputOption=RAW`;
  await fetch(url, {
    method: 'PUT',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ values: headers })
  });
}

export default async (req) => {
  if (req.method === 'OPTIONS') return new Response('', { status: 204, headers: { ...cors, 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS' } });

  const url = new URL(req.url);
  const sheetId = url.searchParams.get('sheetId') || SHEET_ID;

  try {
    const accessToken = await getAccessToken();

    if (req.method === 'GET') {
      if (!sheetId) return new Response(JSON.stringify({ success: false, error: 'Missing sheetId' }), { status: 400, headers: cors });
      const leads = await readLeads(sheetId, accessToken);
      return new Response(JSON.stringify({ success: true, data: leads }), { status: 200, headers: cors });
    }

    if (req.method === 'POST') {
      let body = {};
      try { body = await req.json(); } catch {}
      const sid = body.spreadsheetID || sheetId;
      if (!sid) return new Response(JSON.stringify({ success: false, error: 'Missing spreadsheetID' }), { status: 400, headers: cors });
      await initSheet(sid, accessToken);
      return new Response(JSON.stringify({ success: true, data: 'Sheet initialized' }), { status: 200, headers: cors });
    }

    return new Response('Method Not Allowed', { status: 405, headers: cors });
  } catch (err) {
    return new Response(JSON.stringify({ success: false, error: err.message }), { status: 500, headers: cors });
  }
};

export const config = { path: ['/api/sheets/leads', '/api/sheets/init'] };
