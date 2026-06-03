'use strict';

async function loadSettings() {
  const resp = await fetch('/api/settings');
  if (!resp.ok) return;
  const data = await resp.json();
  const e = data.email || {};

  document.getElementById('enabled').checked        = !!e.enabled;
  document.getElementById('notify_on').value         = e.notify_on        || 'both';
  document.getElementById('smtp_host').value         = e.smtp_host        || '';
  document.getElementById('smtp_port').value         = e.smtp_port        || 587;
  document.getElementById('smtp_use_tls').checked    = e.smtp_use_tls !== false;
  document.getElementById('smtp_user').value         = e.smtp_user        || '';
  document.getElementById('smtp_password').value     = e.smtp_password    || '';
  document.getElementById('from_address').value      = e.from_address     || '';
  document.getElementById('to_addresses').value      = (e.to_addresses    || []).join('\n');
  document.getElementById('subject_template').value  = e.subject_template || '';
  document.getElementById('body_template').value     = e.body_template    || '';
}

function collectSettings() {
  const toRaw = document.getElementById('to_addresses').value;
  const toList = toRaw.split('\n').map(s => s.trim()).filter(Boolean);

  return {
    email: {
      enabled:          document.getElementById('enabled').checked,
      notify_on:        document.getElementById('notify_on').value,
      smtp_host:        document.getElementById('smtp_host').value.trim(),
      smtp_port:        parseInt(document.getElementById('smtp_port').value, 10) || 587,
      smtp_use_tls:     document.getElementById('smtp_use_tls').checked,
      smtp_user:        document.getElementById('smtp_user').value.trim(),
      smtp_password:    document.getElementById('smtp_password').value,
      from_address:     document.getElementById('from_address').value.trim(),
      to_addresses:     toList,
      subject_template: document.getElementById('subject_template').value,
      body_template:    document.getElementById('body_template').value,
    }
  };
}

function showStatus(id, ok, msg) {
  const el = document.getElementById(id);
  el.textContent = msg;
  el.className = 'status-msg ' + (ok ? 'ok' : 'err');
  setTimeout(() => { el.className = 'status-msg'; }, 4000);
}

async function saveSettings() {
  const btn = document.getElementById('save-btn');
  btn.disabled = true;
  try {
    const resp = await fetch('/api/settings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(collectSettings()),
    });
    if (!resp.ok) throw new Error(await resp.text());
    showStatus('save-status', true, 'Saved.');
  } catch (e) {
    showStatus('save-status', false, 'Save failed: ' + e.message);
  } finally {
    btn.disabled = false;
  }
}

async function sendTest() {
  const addr = document.getElementById('test-address').value.trim();
  if (!addr) { showStatus('test-status', false, 'Enter an email address first.'); return; }

  // Save first so the test uses current form values
  await saveSettings();

  try {
    const resp = await fetch('/api/settings/test', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ to_address: addr }),
    });
    if (!resp.ok) {
      const err = await resp.json();
      throw new Error(err.detail || resp.statusText);
    }
    showStatus('test-status', true, `Test email sent to ${addr}`);
  } catch (e) {
    showStatus('test-status', false, 'Failed: ' + e.message);
  }
}

loadSettings();
