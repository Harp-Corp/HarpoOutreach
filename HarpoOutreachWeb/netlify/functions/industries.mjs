// Netlify Function: GET /api/industries
// Returns all industries with NACE codes and key regulations

const INDUSTRIES = [
  { id: 'banking', shortName: 'Banking', naceSection: 'K64', keyRegulations: ['DORA', 'Basel III', 'MiFID II', 'AML6'] },
  { id: 'insurance', shortName: 'Insurance', naceSection: 'K65', keyRegulations: ['Solvency II', 'DORA', 'IDD'] },
  { id: 'assetManagement', shortName: 'Asset Management', naceSection: 'K64.3', keyRegulations: ['AIFMD', 'UCITS', 'MiFID II', 'SFDR'] },
  { id: 'fintech', shortName: 'FinTech', naceSection: 'K64.9', keyRegulations: ['PSD2', 'DORA', 'MiCA', 'AML6'] },
  { id: 'crypto', shortName: 'Crypto / DLT', naceSection: 'K66.1', keyRegulations: ['MiCA', 'DORA', 'AML6', 'TFR'] },
  { id: 'payments', shortName: 'Payments', naceSection: 'K66.19', keyRegulations: ['PSD2', 'DORA', 'AML6', 'Interchange Reg'] },
  { id: 'capitalMarkets', shortName: 'Capital Markets', naceSection: 'K64.9', keyRegulations: ['MiFID II', 'EMIR', 'MAR', 'DORA'] },
  { id: 'wealthManagement', shortName: 'Wealth Management', naceSection: 'K64.3', keyRegulations: ['MiFID II', 'SFDR', 'DORA'] },
  { id: 'reInsurance', shortName: 'Reinsurance', naceSection: 'K65.2', keyRegulations: ['Solvency II', 'DORA'] },
  { id: 'regulatoryTech', shortName: 'RegTech', naceSection: 'J62.0', keyRegulations: ['DORA', 'AI Act', 'GDPR'] },
  { id: 'supTech', shortName: 'SupTech', naceSection: 'J62.0', keyRegulations: ['DORA', 'AI Act', 'EBA Guidelines'] },
  { id: 'auditConsulting', shortName: 'Audit & Consulting', naceSection: 'M69.2', keyRegulations: ['CSRD', 'ESG', 'DORA'] }
];

const cors = { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' };

export default async (req) => {
  if (req.method === 'OPTIONS') return new Response('', { status: 204, headers: { ...cors, 'Access-Control-Allow-Methods': 'GET, OPTIONS' } });
  if (req.method !== 'GET') return new Response('Method Not Allowed', { status: 405, headers: cors });
  return new Response(JSON.stringify({ success: true, data: INDUSTRIES }), { status: 200, headers: cors });
};

export const config = { path: '/api/industries' };
