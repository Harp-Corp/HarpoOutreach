// Netlify Function: POST /api/email-draft
// Generates outreach email via Perplexity AI
export default async (req) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });
  const key = process.env.PERPLEXITY_API_KEY;
  if (!key) return new Response(JSON.stringify({ error: 'PERPLEXITY_API_KEY not set' }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  let body;
  try { body = await req.json(); } catch { return new Response('Bad Request', { status: 400 }); }
  const { leadId, leadName, companyName, industry, language } = body;
  const lang = language || 'de';
  const prompt = `Write a professional B2B cold outreach email in ${lang === 'de' ? 'German' : 'English'} for a RegTech compliance software company contacting ${leadName || 'the compliance manager'} at ${companyName || 'a company'} in the ${industry || 'financial services'} sector. The email should be concise (max 150 words), mention DORA/GDPR/AI Act compliance challenges, and end with a clear CTA. Return JSON with fields: subject (string), body (string). Only return valid JSON, no markdown.`;
  const resp = await fetch('https://api.perplexity.ai/chat/completions', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'sonar', messages: [{ role: 'user', content: prompt }], temperature: 0.4 })
  });
  if (!resp.ok) return new Response(JSON.stringify({ error: `Perplexity error: ${resp.status}` }), { status: 502, headers: { 'Content-Type': 'application/json' } });
  const data = await resp.json();
  let text = data.choices?.[0]?.message?.content || '{}';
  text = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
  let draft;
  try { draft = JSON.parse(text); } catch { draft = { subject: 'RegTech Compliance Solution', body: text }; }
  return new Response(JSON.stringify({ success: true, data: draft }), {
    status: 200, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
  });
};
export const config = { path: '/api/email-draft' };
