// Netlify Function: GET /health
// Health check endpoint

export default async (req) => {
  return new Response(JSON.stringify({ status: 'OK', service: 'HarpoOutreachWeb', timestamp: new Date().toISOString() }), {
    status: 200,
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
  });
};

export const config = { path: '/health' };
