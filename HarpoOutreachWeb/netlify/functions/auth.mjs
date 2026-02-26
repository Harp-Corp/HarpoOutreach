// Netlify Function: GET /api/auth/google, GET /api/auth/callback, GET /api/auth/status, POST /api/auth/logout
// Google OAuth flow
// Note: Since Netlify is serverless (stateless), auth tokens must be stored in env vars (refresh token)

const cors = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' };

export default async (req) => {
  if (req.method === 'OPTIONS') return new Response('', { status: 204, headers: { ...cors, 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS' } });

  const url = new URL(req.url);
  const path = url.pathname;

  // GET /api/auth/google - redirect to Google OAuth
  if (path.endsWith('/google') && req.method === 'GET') {
    const clientId = process.env.GOOGLE_CLIENT_ID;
    const redirectUri = process.env.GOOGLE_REDIRECT_URI || `${url.origin}/api/auth/callback`;
    const scope = encodeURIComponent('https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/spreadsheets');
    const authUrl = `https://accounts.google.com/o/oauth2/v2/auth?client_id=${clientId}&redirect_uri=${encodeURIComponent(redirectUri)}&response_type=code&scope=${scope}&access_type=offline&prompt=consent`;
    return Response.redirect(authUrl, 302);
  }

  // GET /api/auth/callback - handle OAuth callback
  if (path.endsWith('/callback') && req.method === 'GET') {
    const code = url.searchParams.get('code');
    if (!code) return new Response(JSON.stringify({ success: false, error: 'Missing code' }), { status: 400, headers: cors });

    const redirectUri = process.env.GOOGLE_REDIRECT_URI || `${url.origin}/api/auth/callback`;
    const params = new URLSearchParams({
      client_id: process.env.GOOGLE_CLIENT_ID,
      client_secret: process.env.GOOGLE_CLIENT_SECRET,
      code,
      redirect_uri: redirectUri,
      grant_type: 'authorization_code'
    });
    const resp = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', body: params });
    const tokens = await resp.json();
    if (tokens.error) return new Response(JSON.stringify({ success: false, error: tokens.error }), { status: 400, headers: cors });

    // Return refresh token in response (user should add it to Netlify env vars)
    return Response.redirect(`${url.origin}/?auth=success&refresh_token=${tokens.refresh_token || 'already_set'}`, 302);
  }

  // GET /api/auth/status - check auth status using env var refresh token
  if (path.endsWith('/status') && req.method === 'GET') {
    const hasToken = !!(process.env.GOOGLE_REFRESH_TOKEN);
    return new Response(JSON.stringify({ success: true, data: { authenticated: hasToken, email: process.env.GMAIL_SENDER_EMAIL || null } }), { status: 200, headers: cors });
  }

  // POST /api/auth/logout
  if (path.endsWith('/logout') && req.method === 'POST') {
    // Stateless - just return success (token revocation requires manual env var removal)
    return new Response(JSON.stringify({ success: true, data: 'Logged out' }), { status: 200, headers: cors });
  }

  return new Response('Not Found', { status: 404, headers: cors });
};

export const config = { path: ['/api/auth/google', '/api/auth/callback', '/api/auth/status', '/api/auth/logout'] };
