// Netlify Function: POST /api/social
export default async (req) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });
  const key = process.env.PERPLEXITY_API_KEY;
  if (!key) return new Response(JSON.stringify({ error: 'PERPLEXITY_API_KEY not set' }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  let body;
  try { body = await req.json(); } catch { return new Response('Bad Request', { status: 400 }); }
  const { platform, industry, topic } = body;
  const charLimit = platform === 'twitter' ? 280 : platform === 'xing' ? 600 : 1300;
  const prompt = `Write a professional ${platform || 'LinkedIn'} post in German for a RegTech compliance software company. Topic: ${topic || 'DORA compliance challenges'}. Industry focus: ${industry || 'financial services'}. Max ${charLimit} characters. Include relevant hashtags. Return JSON with field: content (string). Only return valid JSON, no markdown.`;
  const resp = await fetch('https://api.perplexity.ai/chat/completions', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'sonar', messages: [{ role: 'user', content: prompt }], temperature: 0.5 })
  });
  if (!resp.ok) return new Response(JSON.stringify({ error: `Perplexity error: ${resp.status}` }), { status: 502, headers: { 'Content-Type': 'application/json' } });
  const data = await resp.json();
  let text = data.choices?.[0]?.message?.content || '{}';
  text = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
  let post;
  try { post = JSON.parse(text); } catch { post = { content: text }; }
  return new Response(JSON.stringify({ success: true, data: post }), {
    status: 200, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
  });
};
export const config = { path: '/api/social' };
