// HarpoOutreach Web - Frontend Application
'use strict';

const API_BASE = '/api';

// --- State ---
let state = {
  industries: [],
  regions: [],
  leads: [],
  currentView: 'dashboard',
  isAuthenticated: false
};

// --- API Helper ---

// --- Toast Notifications ---
function showToast(message, type = 'info') {
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  document.body.appendChild(toast);
  setTimeout(() => toast.classList.add('show'), 100);
  setTimeout(() => {
    toast.classList.remove('show');
    setTimeout(() => toast.remove(), 300);
  }, 3000);
}

async function api(endpoint, options = {}) {
  const url = `${API_BASE}${endpoint}`;
  const config = {
    headers: { 'Content-Type': 'application/json' },
    ...options
  };
  if (config.body && typeof config.body === 'object') {
    config.body = JSON.stringify(config.body);
  }
  try {
    const res = await fetch(url, config);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const ct = res.headers.get('content-type');
    if (ct && ct.includes('application/json')) return res.json();
    return res.text();
  } catch (err) {
    console.error(`API error ${endpoint}:`, err);
    throw err;
  }
}

// --- Navigation ---
function initNavigation() {
  document.querySelectorAll('.nav-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const view = btn.dataset.view;
      switchView(view);
    });
  });
}

function switchView(viewName) {
  state.currentView = viewName;
  document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
  const btn = document.querySelector(`[data-view="${viewName}"]`);
  const view = document.getElementById(`view-${viewName}`);
  if (btn) btn.classList.add('active');
  if (view) view.classList.add('active');
  if (viewName === 'dashboard') loadDashboard();
  if (viewName === 'leads') loadLeads();
}

// --- Populate Dropdowns ---
async function loadIndustries() {
  try {
    const res = await api('/industries');    const selects = ['filter-industry', 'lead-industry', 'search-industry', 'social-industry'];
        state.industries = res.data || res;
    selects.forEach(id => {
      const el = document.getElementById(id);
      if (!el) return;
      const keepFirst = el.options[0];
      el.innerHTML = '';
      if (keepFirst && keepFirst.value === '') el.appendChild(keepFirst);
      state.industries.forEach(ind => {
        const opt = document.createElement('option');
        opt.value = ind.id;
        opt.textContent = ind.shortName || ind.id;
        el.appendChild(opt);
      });
    });
  } catch (e) { console.warn('Could not load industries:', e); }
}

async function loadRegions() {
  try {
    const res = await api('/regions');    const selects = ['filter-region', 'lead-region', 'search-region'];
        state.regions = res.data || res;
    selects.forEach(id => {
      const el = document.getElementById(id);
      if (!el) return;
      const keepFirst = el.options[0];
      el.innerHTML = '';
      if (keepFirst && keepFirst.value === '') el.appendChild(keepFirst);
      state.regions.forEach(reg => {
        const opt = document.createElement('option');
        opt.value = reg.id;
        opt.textContent = reg.id;
        el.appendChild(opt);
      });
    });
  } catch (e) { console.warn('Could not load regions:', e); }
}

// --- Dashboard ---
async function loadDashboard() {
  try {
    const res = await api('/dashboard');    document.getElementById('stat-leads').textContent = stats.totalLeads || 0;
    const stats = res.data || res;
    document.getElementById('stat-emails-sent').textContent = stats.emailsSent || 0;
    document.getElementById('stat-emails-opened').textContent = stats.emailsOpened || 0;
    document.getElementById('stat-responses').textContent = stats.responses || 0;
    document.getElementById('chart-industry').textContent = 'Pipeline-Daten werden geladen...';
    document.getElementById('chart-performance').textContent = 'Performance-Daten werden geladen...';
  } catch (e) {
    console.warn('Dashboard load error:', e);
  }
}

// --- Leads ---
async function loadLeads() {
  try {
    const res = await api('/leads');    renderLeadsTable(state.leads);
        state.leads = res.data || res;
    populateEmailLeadSelect();
  } catch (e) {
    console.warn('Leads load error:', e);
  }
}

function renderLeadsTable(leads) {
  const tbody = document.getElementById('leads-tbody');
  if (!tbody) return;
  if (leads.length === 0) {
    tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--text-secondary);padding:2rem;">Keine Leads vorhanden. Klicke "+ Neuer Lead" um zu beginnen.</td></tr>';
    return;
  }
  tbody.innerHTML = leads.map(l => `
    <tr>
      <td>${esc(l.name)}</td>
      <td>${esc(l.companyName)}</td>
      <td>${esc(l.industry || '')}</td>
      <td>${esc(l.region || '')}</td>
      <td><span class="badge badge-${l.status || 'new'}">${esc(l.status || 'new')}</span></td>
      <td>
        <button class="btn btn-outline" onclick="draftEmailForLead('${esc(l.id)}')" style="padding:0.25rem 0.5rem;font-size:0.75rem;">E-Mail</button>
      </td>
    </tr>
  `).join('');
}

function esc(str) {
  const div = document.createElement('div');
  div.textContent = str || '';
  return div.innerHTML;
}

function initLeadModal() {
  const modal = document.getElementById('modal-lead');
  const btnAdd = document.getElementById('btn-add-lead');
  if (btnAdd) btnAdd.addEventListener('click', () => modal.classList.remove('hidden'));
  modal.querySelectorAll('.modal-close').forEach(btn => {
    btn.addEventListener('click', () => modal.classList.add('hidden'));
  });
  const form = document.getElementById('form-lead');
  if (form) form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const fd = new FormData(form);
    const lead = Object.fromEntries(fd.entries());
    try {
      await api('/leads', { method: 'POST', body: lead });
      modal.classList.add('hidden');
      form.reset();
      loadLeads();
    } catch (err) {
, 'error'      alert('Fehler beim Speichern: ' + err.message);
    }
  }showToast
function initLeadFilters() {
  const filterIndustry = document.getElementById('filter-industry');
  const filterRegion = document.getElementById('filter-region');
  const filterStatus = document.getElementById('filter-status');
  const searchInput = document.getElementById('search-leads');
  const applyFilters = () => {
    let filtered = [...state.leads];
    const ind = filterIndustry ? filterIndustry.value : '';
    const reg = filterRegion ? filterRegion.value : '';
    const st = filterStatus ? filterStatus.value : '';
    const q = searchInput ? searchInput.value.toLowerCase() : '';
    if (ind) filtered = filtered.filter(l => l.industry === ind);
    if (reg) filtered = filtered.filter(l => l.region === reg);
    if (st) filtered = filtered.filter(l => l.status === st);
    if (q) filtered = filtered.filter(l =>
      (l.name || '').toLowerCase().includes(q) ||
      (l.companyName || '').toLowerCase().includes(q)
    );
    renderLeadsTable(filtered);
  };
  [filterIndustry, filterRegion, filterStatus].forEach(el => {
    if (el) el.addEventListener('change', applyFilters);
  });
  if (searchInput) searchInput.addEventListener('input', applyFilters);
}

// --- Companies Search ---
function initCompanySearch() {
  const form = document.getElementById('form-search-companies');
  if (!form) return;
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const resultsDiv = document.getElementById('companies-results');
    resultsDiv.innerHTML = '<div class="loading"></div> Suche laeuft...';
    try {
      const body = {
        industry: document.getElementById('search-industry').value,
        region: document.getElementById('search-region').value,
        companySize: document.getElementById('search-size').value,
        query: document.getElementById('search-query').value
      };
      const res = await api('/companies/search', { method: 'POST', body });
      const companies = res.data || res || [];
      if (companies.length === 0) {
        resultsDiv.innerHTML = '<p style="color:var(--text-secondary);">Keine Firmen gefunden. Versuche andere Suchkriterien.</p>';
        return;
      }
      resultsDiv.innerHTML = companies.map(c => `
        <div class="company-card">
          <h4>${esc(c.name)}</h4>
          <p>${esc(c.description || '')}</p>
          <p><strong>Branche:</strong> ${esc(c.industry || '')} | <strong>Groesse:</strong> ${esc(c.size || '')}</p>
          <button class="btn btn-outline" onclick="addCompanyAsLead(${JSON.stringify(c).replace(/"/g, '&quot;')})">Als Lead hinzufuegen</button>
        </div>
      `).join('');
    } catch (err) {
      resultsDiv.innerHTML = '<p style="color:var(--danger);">Fehler bei der Suche: ' + esc(err.message) + '</p>';
    }
  });

    // Start/Stop Search Button
  let searchAbortController = null;
  const btnStartSearch = document.getElementById('btn-start-search');
  if (btnStartSearch) {
    btnStartSearch.addEventListener('click', async () => {
      if (searchAbortController) {
        // Suche abbrechen
        searchAbortController.abort();
        searchAbortController = null;
        btnStartSearch.textContent = 'Start Suche';
        btnStartSearch.classList.remove('btn-danger');
        btnStartSearch.classList.add('btn-primary');
        const resultsDiv = document.getElementById('companies-results');
        resultsDiv.innerHTML += '<p style="color:var(--warning);">Suche abgebrochen.</p>';
      } else {
        // Suche starten
        btnStartSearch.textContent = 'Suche abbrechen';
        btnStartSearch.classList.remove('btn-primary');
        btnStartSearch.classList.add('btn-danger');
        
        const resultsDiv = document.getElementById('companies-results');
        resultsDiv.innerHTML = '<div class="loading"></div> Suche laeuft...';
        
        searchAbortController = new AbortController();
        
        try {
          const body = {
            industry: document.getElementById('search-industry').value,
            region: document.getElementById('search-region').value,
            companySize: document.getElementById('search-size').value,
            query: document.getElementById('search-query').value
          };
          
          const res = await api('/companies/search', { 
            method: 'POST', 
            body,
            signal: searchAbortController.signal 
          });
          const companies = res.data || res || [];
          
          searchAbortController = null;
          btnStartSearch.textContent = 'Start Suche';
          btnStartSearch.classList.remove('btn-danger');
          btnStartSearch.classList.add('btn-primary');
          
          if (companies.length === 0) {
            resultsDiv.innerHTML = '<p style="color:var(--text-secondary);">Keine Firmen gefunden. Versuche andere Suchkriterien.</p>';
            return;
          }
          
          resultsDiv.innerHTML = companies.map(c => `
            <div class="company-card">
              <h4>\${esc(c.name)}</h4>
              <p>\${esc(c.description || '')}</p>
              <p><strong>Branche:</strong> \${esc(c.industry || '')} | <strong>Groesse:</strong> \${esc(c.size || '')}</p>
              <button class="btn btn-outline" onclick="addCompanyAsLead(\${JSON.stringify(c).replace(/"/g, '&quot;')})">Als Lead hinzufuegen</button>
            </div>
          `).join('');
        } catch (err) {
          searchAbortController = null;
          btnStartSearch.textContent = 'Start Suche';
          btnStartSearch.classList.remove('btn-danger');
          btnStartSearch.classList.add('btn-primary');
          
          if (err.name === 'AbortError') {
            // Abbruch bereits behandelt
            return;
          }
          resultsDiv.innerHTML = '<p style="color:var(--danger);">Fehler bei der Suche: ' + esc(err.message) + '</p>';
        }
      }
    });
  }
}

function addCompanyAsLead(company) {
  document.querySelector('#form-lead [name="companyName"]').value = company.name || '';
  document.querySelector('#form-lead [name="industry"]').value = company.industry || '';
  document.getElementById('modal-lead').classList.remove('hidden');
  switchView('leads');
}

// --- Email ---
function populateEmailLeadSelect() {
  const sel = document.getElementById('email-lead-select');
  if (!sel) return;
  const first = sel.options[0];
  sel.innerHTML = '';
  sel.appendChild(first);
  state.leads.forEach(l => {
    const opt = document.createElement('option');
    opt.value = l.id || '';
    opt.textContent = `${l.name} (${l.companyName})`;
    sel.appendChild(opt);
  });
}

function initEmail() {
  const btnDraft = document.getElementById('btn-draft-email');
  const btnSend = document.getElementById('btn-send-email');

  if (btnDraft) btnDraft.addEventListener('click', async () => {
    const leadId = document.getElementById('email-lead-select').value;
    if (!leadId) { alert('Bitte waehle zuerst einen Lead aus.'); return; }
    btnDraft.textContent = 'Generiere...';
    btnDraft.disabled = true;
    try {
      const res = await api('/email/draft', { method: 'POST', body: { leadId showToast
      const draft = res.data || res;
      document.getElementById('email-subject').value = draft.subject || '';
      document.getElementById('email-body').value = draft.body || '';
    } catch (err) {
, 'error'      alert('Fehler beim Generieren: ' + err.message);
    } finally {
      btnDraft.textContent = 'Entwurf generieren';
      btnDraft.disabled = falseshowToast
  });

  if (btnSend) btnSend.addEventListener('click', async () => {
    const leadId = document.getElementById('email-lead-select').value;
    const subject = document.getElementById('email-subject').value;
    const body = document.getElementById('email-body').value;
    if (!leadId || !subject || !body) { alert('Bitte fuellen alle Felder aus.'); return; }
    btnSend.textContent = 'Sende...';
    btnSend.disabled = true;
    try {
      await api('/email/send', { method: 'POST', body: { leadId, subject, body } });
      alert('E-Mail wurde gesendeshowToast, 'success'
      document.getElementById('email-subject').value = '';
      document.getElementById('email-body').value = '';
    } catch (err) {
      alert('Fehler beim Senden: ' + err.messshowToast, 'error'
    } finally {
      btnSend.textContent = 'Senden';
      btnSend.disabled = false;
    }
  });
}

function draftEmailForLead(leadId) {
  switchView('email');
  const sel = document.getElementById('email-lead-select');
  if (sel) sel.value = leadId;
}

// --- Social Posts ---
function initSocial() {
  const form = document.getElementById('form-social');
  if (!form) return;
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const resultDiv = document.getElementById('social-result');
    const contentDiv = document.getElementById('social-content');
    resultDiv.classList.add('hidden');
    try {
      const body = {
        platform: document.getElementById('social-platform').value,
        industry: document.getElementById('social-industry').value,
        topic: document.getElementById('social-topic').value
      };
      const res = await api('/social/generate', { method: 'POST', body });
      const post = res.data || res;
      contentDiv.textContent = post.content || 'Kein Inhalt generiert.';
      resultDiv.classList.remove('hidden');
    } catch (err) {
      contentDiv.textContent = 'Fehler: ' + err.message;
      resultDiv.classList.remove('hidden');
    }
  });

  const btnCopy = document.getElementById('btn-copy-post');
  if (btnCopy) btnCopy.addEventListener('click', () => {
    const text = document.getElementById('social-content').textContent;
    navigator.clipboard.writeText(text).then(() => {
      btnCopy.textContent = 'Kopiert!';
      setTimeout(() => { btnCopy.textContent = 'In Zwischenablage kopieren'; }, 2000);
    });
  });
}

// --- Google Auth ---
function initAuth() {
  const btn = document.getElementById('btn-auth');
  if (btn) btn.addEventListener('click', async () => {
    try {
      const res = await api('/auth/google');
      if (res && res.startsWith && res.startsWith('http')) {
        window.location.href = res;
      } else {
        alert('OAuth Flow wird konfiguriert. Bitte Server-Einstellungen pruefen.');
      }
    } catch (err) {
      alert('Auth-Fehler: ' + err.message);
    }
  });
}

// --- Health Check ---
async function checkHealth() {
  const el = document.getElementById('health-status');
  try {
    const res = await fetch('/health');
    if (res.ok) {
      el.textContent = 'Server verbunden';
      el.className = 'health-indicator connected';
    } else {
      throw new Error('Not OK');
    }
  } catch {
    el.textContent = 'Server nicht erreichbar';
    el.className = 'health-indicator error';
  }
}

// --- Init ---
document.addEventListener('DOMContentLoaded', async () => {
  initNavigation();
  initLeadModal();
  initLeadFilters();
  initCompanySearch();
  initEmail();
  initSocial();
  initAuth();

  await Promise.all([
    loadIndustries(),
    loadRegions(),
    checkHealth()
  ]);

  loadDashboard();
});
