// Netlify Function: GET /api/dashboard
// Returns dashboard statistics (stored in leads in-memory or Sheets)

const cors = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' };

export default async (req) => {
  if (req.method === 'OPTIONS') return new Response('', { status: 204, headers: { ...cors, 'Access-Control-Allow-Methods': 'GET, OPTIONS' } });
  if (req.method !== 'GET') return new Response('Method Not Allowed', { status: 405, headers: cors });

  // Dashboard stats - can be extended to pull from Google Sheets
  const stats = {
    totalLeads: 0,
    newLeads: 0,
    emailsSent: 0,
    repliesReceived: 0,
    conversionRate: 0,
    topIndustries: [],
    topRegions: [],
    lastUpdated: new Date().toISOString()
  };

  return new Response(JSON.stringify({ success: true, data: stats }), { status: 200, headers: cors });
};

export const config = { path: '/api/dashboard' };
