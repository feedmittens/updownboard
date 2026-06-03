'use strict';

const POLL_MS = 15000;
let systems = {};

// ── Data ─────────────────────────────────────────
async function fetchSystems() {
  try {
    const resp = await fetch('/api/systems');
    if (!resp.ok) throw new Error(resp.statusText);
    systems = await resp.json();
    renderGrid();
    document.getElementById('last-updated').textContent =
      'Last updated: ' + new Date().toLocaleTimeString();
  } catch (e) {
    document.getElementById('last-updated').textContent = 'Error: ' + e.message;
  }
}

// ── Rendering ─────────────────────────────────────
function renderGrid() {
  const grid = document.getElementById('grid');
  const names = Object.keys(systems);

  if (names.length === 0) {
    grid.innerHTML = '<p id="empty-msg">No systems configured. Add systems to config.yaml and restart.</p>';
    return;
  }

  // Track existing tiles by name so we can update in place
  const existing = {};
  grid.querySelectorAll('.tile[data-name]').forEach(el => { existing[el.dataset.name] = el; });

  // Remove stale tiles
  Object.keys(existing).forEach(n => { if (!systems[n]) existing[n].remove(); });

  names.forEach(name => {
    const d = systems[name];
    const state = d.state || 'UNKNOWN';
    const cls = state === 'GREEN' ? 'green' : state === 'RED' ? 'red' : 'unknown';

    if (existing[name]) {
      existing[name].className = `tile ${cls}`;
      existing[name].querySelector('.tile-badge').textContent = state;
    } else {
      const tile = document.createElement('div');
      tile.className = `tile ${cls}`;
      tile.dataset.name = name;
      tile.innerHTML = `<div class="tile-name">${esc(name)}</div><div class="tile-badge">${state}</div>`;
      tile.addEventListener('click', () => showModal(name));
      grid.appendChild(tile);
    }
  });
}

// ── Modal ─────────────────────────────────────────
function showModal(name) {
  const d = systems[name];
  if (!d) return;

  document.getElementById('modal-title').textContent = name;
  document.getElementById('modal-state').textContent = `Status: ${d.state}  —  ${d.reason || ''}`;

  const failed = d.failed_checks || [];
  const checksEl = document.getElementById('modal-checks');

  if (d.state === 'GREEN') {
    checksEl.innerHTML = '<div class="check-row pass">All checks passing</div>';
  } else {
    checksEl.innerHTML = failed.map(c =>
      `<div class="check-row fail"><strong>${esc(c.type)}</strong>: ${esc(c.message)}</div>`
    ).join('');
  }

  document.getElementById('modal-time').textContent =
    d.last_checked ? 'Last checked: ' + new Date(d.last_checked).toLocaleString() : '';

  document.getElementById('modal').classList.remove('hidden');
}

function hideModal() {
  document.getElementById('modal').classList.add('hidden');
}

// ── Utilities ─────────────────────────────────────
function esc(s) {
  if (!s) return '';
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ── Wire-up ───────────────────────────────────────
document.getElementById('modal-close').addEventListener('click', hideModal);
document.getElementById('modal').addEventListener('click', e => {
  if (e.target === document.getElementById('modal')) hideModal();
});
document.addEventListener('keydown', e => { if (e.key === 'Escape') hideModal(); });

fetchSystems();
setInterval(fetchSystems, POLL_MS);
