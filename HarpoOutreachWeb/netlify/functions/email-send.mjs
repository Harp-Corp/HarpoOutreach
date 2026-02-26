// Netlify Function: POST /api/email/send, POST /api/email/replies
// Gmail integration via OAuth refresh token

const cors = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' };

async function getAccessToken() {
  const params = new URLSearchParams({
    client_id: process.env.GOOGLE_CLIENT_ID,
    client_secret: process.env.GOOGLE_CLIENT_SECRET,
    refresh_token: process.env.GOOGLE_REFRESH_TOKEN,
    grant_type: 'refresh_token'
  });
  const resp = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', body: params });
  const data = await resp.json();
  if (!data.access_token) throw new Error('Failed to get access token: ' + JSON.stringify(data));
  return data.access_token;
}

function encodeEmail(to, from, subject, body) {
  const msg = [
    `To: ${to}`,
    `From: ${from}`,
    `Subject: ${subject}`,
    'Content-Type: text/html; charset=UTF-8',
    '',
    body
  ].join('\r\n');
  return btoa(unescape(encodeURIComponent(msg)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export default async (req) => {
  if (req.method === 'OPTIONS') return new Response('', { status: 204, headers: { ...cors, 'Access-Control-Allow-Methods': 'POST, OPTIONS' } });
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405, headers: cors });

  const url = new URL(req.url);
  const path = url.pathname;

  try {
    const accessToken = await getAccessToken();
    const body = await req.json();

    if (path.endsWith('/send')) {
      const { to, from, subject, body: emailBody } = body;
      if (!to || !subject || !emailBody) {
        return new Response(JSON.stringify({ success: false, error: 'Missing required fields: to, subject, body' }), { status: 400, headers: cors });
      }
      const sender = from || process.env.GMAIL_SENDER_EMAIL;
      const raw = encodeEmail(to, sender, subject, emailBody);
      const resp = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/messages/send', {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ raw })
      });
      const result = await resp.json();
      if (result.error) throw new Error(result.error.message);
      return new Response(JSON.stringify({ success: true, data: result.id }), { status: 200, headers: cors });
    }

    if (path.endsWith('/replies')) {
      const { sentSubjects = [], leadEmails = [] } = body;
      const query = sentSubjects.map(s => `subject:Re: ${s}`).join(' OR ');
      const resp = await fetch(`https://gmail.googleapis.com/gmail/v1/users/me/messages?q=${encodeURIComponent(query)}&maxResults=50`, {
        headers: { Authorization: `Bearer ${accessToken}` }
      });
      const data = await resp.json();
      return new Response(JSON.stringify({ success: true, data: data.messages || [] }), { status: 200, headers: cors });
    }

    return new Response('Not Found', { status: 404, headers: cors });
  } catch (err) {
    return new Response(JSON.stringify({ success: false, error: err.message }), { status: 500, headers: cors });
  }
};

export const config = { path: ['/api/email/send', '/api/email/replies'] };
