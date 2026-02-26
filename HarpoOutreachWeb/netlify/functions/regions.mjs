// Netlify Function: GET /api/regions
// Returns all regions with country lists

const REGIONS = [
  { id: 'dach', name: 'DACH', countries: ['DE', 'AT', 'CH'] },
  { id: 'benelux', name: 'Benelux', countries: ['BE', 'NL', 'LU'] },
  { id: 'nordics', name: 'Nordics', countries: ['SE', 'NO', 'DK', 'FI', 'IS'] },
  { id: 'baltics', name: 'Baltics', countries: ['EE', 'LV', 'LT'] },
  { id: 'cee', name: 'CEE', countries: ['PL', 'CZ', 'SK', 'HU', 'RO', 'BG', 'HR', 'SI'] },
  { id: 'westernEurope', name: 'Western Europe', countries: ['GB', 'FR', 'ES', 'PT', 'IT', 'IE'] },
  { id: 'southernEurope', name: 'Southern Europe', countries: ['IT', 'GR', 'CY', 'MT'] },
  { id: 'eu27', name: 'EU-27', countries: ['AT','BE','BG','CY','CZ','DE','DK','EE','ES','FI','FR','GR','HR','HU','IE','IT','LT','LU','LV','MT','NL','PL','PT','RO','SE','SI','SK'] },
  { id: 'eea', name: 'EEA', countries: ['EU-27', 'IS', 'LI', 'NO'] },
  { id: 'global', name: 'Global', countries: ['*'] }
];

const cors = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' };

export default async (req) => {
  if (req.method === 'OPTIONS') return new Response('', { status: 204, headers: { ...cors, 'Access-Control-Allow-Methods': 'GET, OPTIONS' } });
  if (req.method !== 'GET') return new Response('Method Not Allowed', { status: 405, headers: cors });
  return new Response(JSON.stringify({ success: true, data: REGIONS }), { status: 200, headers: cors });
};

export const config = { path: '/api/regions' };
