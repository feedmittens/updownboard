'use strict';

// ── Check type definitions ────────────────────────────────────────────────────
const CHECK_TYPES = {
  ping: {
    label: 'ping',
    params: [
      { key: 'count',   label: 'Count',   type: 'number', placeholder: '1',  width: 80 },
      { key: 'timeout', label: 'Timeout', type: 'number', placeholder: '3s', width: 80 },
    ],
  },
  tcp: {
    label: 'tcp',
    params: [
      { key: 'port',    label: 'Port',    type: 'number', placeholder: '22',  width: 90, required: true },
      { key: 'label',   label: 'Label',   type: 'text',   placeholder: 'SSH', width: 120 },
      { key: 'timeout', label: 'Timeout', type: 'number', placeholder: '5s',  width: 80 },
    ],
  },
  http: {
    label: 'http',
    params: [
      { key: 'url',           label: 'URL',            type: 'text',   placeholder: 'https://example.com', width: 260, required: true },
      { key: 'expect_status', label: 'Expect status',  type: 'number', placeholder: '200',                 width: 110 },
      { key: 'label',         label: 'Label',          type: 'text',   placeholder: 'Web UI',              width: 120 },
      { key: 'timeout',       label: 'Timeout',        type: 'number', placeholder: '10s',                 width: 80 },
    ],
  },
  ssh_metrics: {
    label: 'ssh_metrics',
    params: [
      { key: 'username', label: 'Username', type: 'text',   placeholder: 'monitor',          width: 130, required: true },
      { key: 'key_file', label: 'Key file', type: 'text',   placeholder: '~/.ssh/id_ed25519', width: 200, required: true },
      { key: 'port',     label: 'Port',     type: 'number', placeholder: '22',               width: 80 },
    ],
  },
  snmp: {
    label: 'snmp',
    params: [
      { key: 'community', label: 'Community', type: 'text',   placeholder: 'public',              width: 120 },
      { key: 'oid',       label: 'OID',       type: 'text',   placeholder: '1.3.6.1.2.1.1.1.0',  width: 220 },
      { key: 'port',      label: 'Port',      type: 'number', placeholder: '161',                 width: 80 },
    ],
  },
};

let _systems = [];   // mutable working copy
let _sysCounter = 0; // stable IDs for DOM references

// ── Load ─────────────────────────────────────────────────────────────────────
async function loadConfig() {
  const resp = await fetch('/api/config');
  if (!resp.ok) { showStatus('err', 'Failed to load config'); return; }
  const data = await resp.json();

  const s = data.settings || {};
  document.getElementById('poll_interval').value = s.poll_interval ?? 30;
  document.getElementById('history_limit').value = s.history_limit ?? 500;

  _systems = (data.systems || []).map(sys => ({
    _id: ++_sysCounter,
    name: sys.name || '',
    host: sys.host || '',
    checks: (sys.checks || []).map(normaliseCheck),
  }));

  renderSystems();
}

function normaliseCheck(c) {
  const type = c.type || 'ping';
  const params = {};
  const known = (CHECK_TYPES[type]?.params || []).map(p => p.key);
  for (const k of known) {
    if (c[k] !== undefined && c[k] !== null && c[k] !== '') params[k] = c[k];
  }
  return { type, params };
}

// ── Render ────────────────────────────────────────────────────────────────────
function renderSystems() {
  const container = document.getElementById('systems-list');
  container.innerHTML = '';
  _systems.forEach(sys => container.appendChild(buildSystemBlock(sys)));
}

function buildSystemBlock(sys) {
  const block = document.createElement('div');
  block.className = 'system-block open';
  block.dataset.id = sys._id;

  const checksHtml = sys.checks.map((c, ci) => buildCheckRowHtml(sys._id, ci, c)).join('');

  block.innerHTML = `
    <div class="system-header" onclick="toggleSystem(${sys._id})">
      <span class="system-chevron">&#9654;</span>
      <span class="system-name-display">${esc(sys.name) || '<unnamed>'}</span>
      <span class="system-host-display">${esc(sys.host)}</span>
      <button class="btn-icon" title="Remove system"
        onclick="event.stopPropagation(); removeSystem(${sys._id})">&#215;</button>
    </div>
    <div class="system-body">
      <div class="system-fields">
        <div class="row-2" style="margin-bottom:0.6rem">
          <div class="field">
            <label>Name</label>
            <input type="text" value="${esc(sys.name)}" placeholder="Router"
              oninput="updateSystem(${sys._id}, 'name', this.value)">
          </div>
          <div class="field">
            <label>Host <span class="hint">IP or hostname</span></label>
            <input type="text" value="${esc(sys.host)}" placeholder="10.0.0.1"
              oninput="updateSystem(${sys._id}, 'host', this.value)">
          </div>
        </div>
      </div>
      <div class="checks-label">Checks</div>
      <div class="checks-container" id="checks-${sys._id}">${checksHtml}</div>
      <button class="add-check-btn" onclick="addCheck(${sys._id})">&#43; Add check</button>
    </div>`;

  return block;
}

function buildCheckRowHtml(sysId, checkIdx, check) {
  const typeOpts = Object.keys(CHECK_TYPES)
    .map(t => `<option value="${t}" ${t === check.type ? 'selected' : ''}>${t}</option>`)
    .join('');

  const paramsHtml = buildParamFieldsHtml(sysId, checkIdx, check);

  return `
    <div class="check-row" id="check-${sysId}-${checkIdx}">
      <div class="check-row-inner">
        <div class="check-type-row">
          <select class="check-type-select"
            onchange="changeCheckType(${sysId}, ${checkIdx}, this.value)">${typeOpts}</select>
        </div>
        <div class="check-params" id="params-${sysId}-${checkIdx}">${paramsHtml}</div>
      </div>
      <button class="btn-icon" title="Remove check"
        onclick="removeCheck(${sysId}, ${checkIdx})">&#215;</button>
    </div>`;
}

function buildParamFieldsHtml(sysId, checkIdx, check) {
  const defs = CHECK_TYPES[check.type]?.params || [];
  return defs.map(p => {
    const val = check.params[p.key] !== undefined ? esc(String(check.params[p.key])) : '';
    const req  = p.required ? '*' : '';
    return `
      <div class="param-field" style="max-width:${p.width + 20}px">
        <label>${p.label}${req}</label>
        <input type="${p.type}" value="${val}" placeholder="${p.placeholder}"
          oninput="updateCheckParam(${sysId}, ${checkIdx}, '${p.key}', this.value)">
      </div>`;
  }).join('');
}

// ── Mutations ─────────────────────────────────────────────────────────────────
function toggleSystem(id) {
  document.querySelector(`.system-block[data-id="${id}"]`).classList.toggle('open');
}

function updateSystem(id, field, value) {
  const sys = _systems.find(s => s._id === id);
  if (!sys) return;
  sys[field] = value;
  // Update header display without full re-render
  const block = document.querySelector(`.system-block[data-id="${id}"]`);
  block.querySelector('.system-name-display').textContent = value || '<unnamed>';
  if (field === 'host') block.querySelector('.system-host-display').textContent = value;
}

function removeSystem(id) {
  _systems = _systems.filter(s => s._id !== id);
  document.querySelector(`.system-block[data-id="${id}"]`)?.remove();
}

function addSystem() {
  const sys = { _id: ++_sysCounter, name: '', host: '', checks: [] };
  _systems.push(sys);
  const block = buildSystemBlock(sys);
  document.getElementById('systems-list').appendChild(block);
  block.querySelector('input').focus();
}

function addCheck(sysId) {
  const sys = _systems.find(s => s._id === sysId);
  if (!sys) return;
  const check = { type: 'ping', params: {} };
  sys.checks.push(check);
  const ci = sys.checks.length - 1;
  const container = document.getElementById(`checks-${sysId}`);
  container.insertAdjacentHTML('beforeend', buildCheckRowHtml(sysId, ci, check));
}

function removeCheck(sysId, checkIdx) {
  const sys = _systems.find(s => s._id === sysId);
  if (!sys) return;
  sys.checks.splice(checkIdx, 1);
  // Re-render just the checks for this system to fix indices
  const container = document.getElementById(`checks-${sysId}`);
  container.innerHTML = sys.checks.map((c, ci) => buildCheckRowHtml(sysId, ci, c)).join('');
}

function changeCheckType(sysId, checkIdx, newType) {
  const sys = _systems.find(s => s._id === sysId);
  if (!sys) return;
  sys.checks[checkIdx] = { type: newType, params: {} };
  document.getElementById(`params-${sysId}-${checkIdx}`).innerHTML =
    buildParamFieldsHtml(sysId, checkIdx, sys.checks[checkIdx]);
}

function updateCheckParam(sysId, checkIdx, key, value) {
  const sys = _systems.find(s => s._id === sysId);
  if (!sys) return;
  const check = sys.checks[checkIdx];
  if (value === '') {
    delete check.params[key];
  } else {
    check.params[key] = value;
  }
}

// ── Save ──────────────────────────────────────────────────────────────────────
async function saveConfig() {
  const btn = document.getElementById('save-btn');
  btn.disabled = true;

  const payload = {
    settings: {
      poll_interval: parseInt(document.getElementById('poll_interval').value, 10) || 30,
      history_limit: parseInt(document.getElementById('history_limit').value, 10) || 500,
    },
    systems: _systems.map(sys => {
      const checks = sys.checks.map(c => {
        const out = { type: c.type };
        const defs = CHECK_TYPES[c.type]?.params || [];
        for (const p of defs) {
          const v = c.params[p.key];
          if (v !== undefined && v !== '') {
            out[p.key] = p.type === 'number' ? Number(v) : v;
          }
        }
        return out;
      });
      return { name: sys.name, host: sys.host, checks };
    }),
  };

  try {
    const resp = await fetch('/api/config', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    if (!resp.ok) {
      const err = await resp.json();
      throw new Error(err.detail || resp.statusText);
    }
    const result = await resp.json();
    showStatus('ok', `Saved & applied — ${result.systems} system${result.systems !== 1 ? 's' : ''} active`);
  } catch (e) {
    showStatus('err', 'Error: ' + e.message);
  } finally {
    btn.disabled = false;
  }
}

// ── Utilities ─────────────────────────────────────────────────────────────────
function showStatus(type, msg) {
  const el = document.getElementById('save-status');
  el.textContent = msg;
  el.className = 'status-msg ' + type;
  setTimeout(() => { el.className = 'status-msg'; }, 5000);
}

function esc(s) {
  if (s == null) return '';
  return String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;')
    .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

loadConfig();
