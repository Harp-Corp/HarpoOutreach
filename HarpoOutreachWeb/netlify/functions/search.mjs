// Netlify Function: POST /api/search
// Replaces Vapor POST /api/v1/companies/search
export default async (req) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });
  const key = process.env.PERPLEXITY_API_KEY;
  if (!key) return new Response(JSON.stringify({ error: 'PERPLEXITY_API_KEY not set' }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  let body;
  try { body = await req.json(); } catch { return new Response('Bad Request', { status: 400 }); }
  const { industry, region, companySize, query } = body;
  const prompt = `Find ${query ? query + ' ' : ''}companies in the ${industry || 'RegTech'} sector in ${region || 'DACH'} region${companySize && companySize !== 'any' ? `, company size: ${companySize}` : ''}. Return a JSON array of 10 companies with fields: name, description, website, size, industry. Only return valid JSON array, no markdown.`;
  const resp = await fetch('https://api.perplexity.ai/chat/completions', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'sonar', messages: [{ role: 'user', content: prompt }], temperature: 0.2 })
  });
  if (!resp.ok) return new Response(JSON.stringify({ error: `Perplexity error: ${resp.status}` }), { status: 502, headers: { 'Content-Type': 'application/json' } });
  const data = await resp.json();
  let text = data.choices?.[0]?.message?.content || '[]';
  text = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
  let companies;
  try { companies = JSON.parse(text); } catch { companies = [{ name: 'Parse error', description: text.substring(0, 200) }]; }
  return new Response(JSON.stringify({ success: true, data: companies }), {
    status: 200, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
  });
};
export const config = { path: '/api/search' };
