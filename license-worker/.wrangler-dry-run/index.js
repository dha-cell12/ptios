var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/dashboard.js
function renderAdminDashboard(nonce) {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex,nofollow">
  <title>TLinkauto License Dashboard</title>
  <style nonce="${nonce}">
    :root {
      color-scheme: light;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #f4f6f8;
      color: #18202a;
      font-synthesis: none;
    }
    * { box-sizing: border-box; }
    body { margin: 0; min-width: 320px; background: #f4f6f8; }
    button, input, select { font: inherit; }
    button { cursor: pointer; }
    button:disabled { cursor: not-allowed; opacity: .55; }
    .hidden { display: none !important; }
    .shell { width: min(1180px, calc(100% - 32px)); margin: 0 auto; padding: 24px 0 48px; }
    .topbar {
      display: flex; align-items: center; justify-content: space-between; gap: 16px;
      min-height: 56px; margin-bottom: 20px;
    }
    .brand { display: flex; align-items: center; gap: 12px; min-width: 0; }
    .brand-mark {
      display: grid; place-items: center; width: 38px; height: 38px; border-radius: 8px;
      color: #fff; background: #1677ff; font-size: 18px; font-weight: 800;
    }
    h1 { margin: 0; font-size: 22px; line-height: 1.2; letter-spacing: 0; }
    .muted { color: #687384; }
    .small { font-size: 13px; }
    .actions { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
    .button {
      min-height: 38px; padding: 0 14px; border: 1px solid #d7dde5; border-radius: 7px;
      background: #fff; color: #263140; font-weight: 650;
    }
    .button:hover { background: #f7f9fb; }
    .button.primary { border-color: #1677ff; background: #1677ff; color: #fff; }
    .button.primary:hover { background: #0868e8; }
    .button.danger { border-color: #e7b6ba; color: #b4232c; background: #fff; }
    .button.quiet { min-width: 38px; padding: 0 10px; }
    .panel {
      border: 1px solid #dfe4ea; border-radius: 8px; background: #fff;
      box-shadow: 0 2px 10px rgba(24, 32, 42, .04);
    }
    .auth-panel { width: min(460px, 100%); margin: 90px auto 0; padding: 24px; }
    .auth-panel h2 { margin: 0 0 8px; font-size: 20px; }
    .auth-panel p { margin: 0 0 20px; line-height: 1.5; }
    .field { display: grid; gap: 7px; }
    .field label, .legend { color: #394555; font-size: 13px; font-weight: 700; }
    .input, .select {
      width: 100%; min-height: 40px; padding: 8px 10px; border: 1px solid #cfd6df;
      border-radius: 6px; background: #fff; color: #18202a; outline: none;
    }
    .input:focus, .select:focus { border-color: #1677ff; box-shadow: 0 0 0 3px rgba(22, 119, 255, .12); }
    .auth-row { display: grid; grid-template-columns: 1fr auto; gap: 8px; }
    .notice {
      display: none; margin: 0 0 16px; padding: 10px 12px; border: 1px solid #c7dafa;
      border-radius: 6px; background: #eef5ff; color: #17457f; font-size: 14px;
    }
    .notice.show { display: block; }
    .notice.error { border-color: #efc2c6; background: #fff1f2; color: #9f1f28; }
    .notice.success { border-color: #b8dfc7; background: #eefaf2; color: #176b36; }
    .status-dot { width: 8px; height: 8px; border-radius: 50%; background: #22a447; }
    .connected { display: inline-flex; align-items: center; gap: 7px; color: #476071; font-size: 13px; }
    .stats {
      display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 1px;
      overflow: hidden; margin-bottom: 16px; border: 1px solid #dfe4ea; border-radius: 8px;
      background: #dfe4ea;
    }
    .stat { min-height: 86px; padding: 16px; background: #fff; }
    .stat-value { display: block; margin-bottom: 5px; font-size: 24px; font-weight: 750; }
    .stat-label { color: #687384; font-size: 13px; }
    .toolbar {
      display: grid; grid-template-columns: minmax(220px, 1fr) 180px auto;
      gap: 10px; padding: 14px; border-bottom: 1px solid #e3e7ec;
    }
    .table-wrap { overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: 13px 14px; border-bottom: 1px solid #e8ebef; text-align: left; vertical-align: middle; }
    th { color: #627080; background: #fafbfc; font-size: 12px; font-weight: 750; text-transform: uppercase; }
    tbody tr:last-child td { border-bottom: 0; }
    tbody tr:hover { background: #fbfcfd; }
    .id-cell { max-width: 260px; font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: 13px; }
    .features { display: flex; gap: 5px; flex-wrap: wrap; }
    .tag {
      display: inline-flex; padding: 3px 7px; border-radius: 5px; background: #edf2f7;
      color: #435064; font-size: 11px; font-weight: 700;
    }
    .badge {
      display: inline-flex; align-items: center; padding: 4px 8px; border-radius: 5px;
      font-size: 12px; font-weight: 750;
    }
    .badge.active { color: #176b36; background: #eaf8ef; }
    .badge.revoked { color: #9f1f28; background: #fff0f1; }
    .badge.expired { color: #8a5700; background: #fff6df; }
    .empty { padding: 42px 20px; text-align: center; color: #687384; }
    .pagination {
      display: flex; align-items: center; justify-content: space-between; gap: 12px;
      padding: 12px 14px; border-top: 1px solid #e3e7ec;
    }
    dialog {
      width: min(680px, calc(100% - 24px)); max-height: calc(100vh - 32px); padding: 0;
      border: 1px solid #d8dee6; border-radius: 8px; background: #fff; color: #18202a;
      box-shadow: 0 18px 50px rgba(20, 28, 38, .22);
    }
    dialog::backdrop { background: rgba(17, 24, 33, .42); }
    .dialog-head {
      display: flex; align-items: center; justify-content: space-between; gap: 12px;
      padding: 17px 18px; border-bottom: 1px solid #e4e8ed;
    }
    .dialog-head h2 { margin: 0; font-size: 18px; }
    .dialog-body { display: grid; gap: 16px; padding: 18px; overflow: auto; }
    .dialog-foot {
      display: flex; align-items: center; justify-content: flex-end; gap: 8px;
      padding: 14px 18px; border-top: 1px solid #e4e8ed; background: #fafbfc;
    }
    .grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }
    .checkboxes { display: flex; flex-wrap: wrap; gap: 8px 14px; }
    .check { display: inline-flex; align-items: center; gap: 7px; font-size: 14px; }
    .check input { width: 16px; height: 16px; }
    .key-result {
      padding: 12px; border: 1px solid #b8dfc7; border-radius: 6px; background: #eefaf2;
    }
    .key-row { display: grid; grid-template-columns: 1fr auto; gap: 8px; margin-top: 8px; }
    .danger-zone { padding-top: 16px; border-top: 1px solid #e3e7ec; }
    .device-list { border: 1px solid #e1e5ea; border-radius: 6px; overflow: hidden; }
    .device {
      display: grid; grid-template-columns: minmax(0, 1fr) auto auto; gap: 10px;
      align-items: center; padding: 11px 12px; border-bottom: 1px solid #e7ebef;
    }
    .device:last-child { border-bottom: 0; }
    .device-id { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-family: ui-monospace, monospace; font-size: 12px; }
    .loading { opacity: .58; pointer-events: none; }
    @media (max-width: 760px) {
      .shell { width: min(100% - 20px, 1180px); padding-top: 12px; }
      .topbar { align-items: flex-start; flex-direction: column; }
      .topbar .actions { width: 100%; }
      .topbar .actions .button { flex: 1; }
      .topbar .actions .connected { display: none; }
      .stats { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .stat:last-child { grid-column: span 2; }
      .toolbar { grid-template-columns: 1fr; }
      .grid-2 { grid-template-columns: 1fr; }
      .hide-mobile, .license-expiry { display: none; }
      th, td { padding: 11px 8px; }
      td .button { min-height: 34px; padding: 0 8px; }
      .id-cell { max-width: 112px; overflow-wrap: anywhere; }
      .device { grid-template-columns: minmax(0, 1fr) auto; }
      .device .device-seen { display: none; }
    }
  </style>
</head>
<body>
  <main class="shell">
    <header class="topbar">
      <div class="brand">
        <div class="brand-mark">TL</div>
        <div>
          <h1>TLinkauto Licenses</h1>
          <div class="muted small">Cloudflare Worker administration</div>
        </div>
      </div>
      <div id="top-actions" class="actions hidden">
        <span class="connected"><span class="status-dot"></span>Connected</span>
        <button id="refresh-button" class="button quiet" type="button" title="Refresh licenses">Refresh</button>
        <button id="new-button" class="button primary" type="button">New License</button>
        <button id="lock-button" class="button quiet" type="button" title="Forget admin token">Lock</button>
      </div>
    </header>

    <div id="notice" class="notice" role="status" aria-live="polite"></div>

    <section id="auth-view" class="panel auth-panel">
      <h2>Administrator access</h2>
      <p class="muted">Enter the Worker <strong>ADMIN_TOKEN</strong>. It remains in this page's memory only and is cleared when you lock or close the tab.</p>
      <form id="auth-form">
        <div class="field">
          <label for="admin-token">Admin token</label>
          <div class="auth-row">
            <input id="admin-token" class="input" type="password" autocomplete="current-password" required>
            <button class="button primary" type="submit">Connect</button>
          </div>
        </div>
      </form>
    </section>

    <section id="dashboard-view" class="hidden">
      <div class="stats" aria-label="License summary">
        <div class="stat"><strong id="stat-total" class="stat-value">0</strong><span class="stat-label">Total licenses</span></div>
        <div class="stat"><strong id="stat-active" class="stat-value">0</strong><span class="stat-label">Active</span></div>
        <div class="stat"><strong id="stat-revoked" class="stat-value">0</strong><span class="stat-label">Revoked</span></div>
        <div class="stat"><strong id="stat-expired" class="stat-value">0</strong><span class="stat-label">Expired</span></div>
        <div class="stat"><strong id="stat-devices" class="stat-value">0</strong><span class="stat-label">Active devices</span></div>
      </div>

      <section id="license-panel" class="panel">
        <div class="toolbar">
          <input id="search-input" class="input" type="search" placeholder="Search license ID">
          <select id="status-filter" class="select" aria-label="Filter by status">
            <option value="all">All states</option>
            <option value="active">Active</option>
            <option value="expired">Expired</option>
            <option value="revoked">Revoked</option>
          </select>
          <span id="result-count" class="muted small"></span>
        </div>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th>License ID</th>
                <th>Status</th>
                <th class="license-expiry">Expiration</th>
                <th>Devices</th>
                <th class="hide-mobile">Features</th>
                <th class="hide-mobile">Updated</th>
                <th></th>
              </tr>
            </thead>
            <tbody id="license-rows"></tbody>
          </table>
          <div id="empty-state" class="empty hidden">No licenses match this view.</div>
        </div>
        <div class="pagination">
          <span id="page-label" class="muted small"></span>
          <div class="actions">
            <button id="previous-button" class="button quiet" type="button">Previous</button>
            <button id="next-button" class="button quiet" type="button">Next</button>
          </div>
        </div>
      </section>
    </section>
  </main>

  <dialog id="create-dialog">
    <form id="create-form">
      <div class="dialog-head">
        <h2>Create License</h2>
        <button class="button quiet" data-close="create-dialog" type="button" aria-label="Close">Close</button>
      </div>
      <div class="dialog-body">
        <div id="created-key-result" class="key-result hidden">
          <strong>License created. Store this key now.</strong>
          <div class="muted small">The Worker stores only its SHA-256 hash, so this clear key cannot be recovered later.</div>
          <div class="key-row">
            <input id="created-key" class="input" type="text" readonly>
            <button id="copy-key-button" class="button" type="button">Copy</button>
          </div>
        </div>
        <div class="field">
          <label for="create-key">License key</label>
          <div class="key-row">
            <input id="create-key" class="input" type="text" maxlength="128" required>
            <button id="generate-key-button" class="button" type="button">Generate</button>
          </div>
        </div>
        <div class="grid-2">
          <div class="field">
            <label for="create-max-devices">Maximum devices</label>
            <input id="create-max-devices" class="input" type="number" min="1" max="1000" value="1" required>
          </div>
          <div class="field">
            <label for="create-expiry">License expiration</label>
            <input id="create-expiry" class="input" type="datetime-local">
            <span class="muted small">Leave blank for no license expiration.</span>
          </div>
        </div>
        <fieldset class="field">
          <legend class="legend">Features</legend>
          <div id="create-features" class="checkboxes"></div>
        </fieldset>
      </div>
      <div class="dialog-foot">
        <button class="button" data-close="create-dialog" type="button">Cancel</button>
        <button id="create-submit" class="button primary" type="submit">Create License</button>
      </div>
    </form>
  </dialog>

  <dialog id="manage-dialog">
    <form id="manage-form">
      <div class="dialog-head">
        <div>
          <h2>Manage License</h2>
          <div id="manage-id" class="muted small"></div>
        </div>
        <button class="button quiet" data-close="manage-dialog" type="button" aria-label="Close">Close</button>
      </div>
      <div class="dialog-body">
        <div class="grid-2">
          <div class="field">
            <label for="manage-status">Status</label>
            <select id="manage-status" class="select">
              <option value="active">Active</option>
              <option value="revoked">Revoked</option>
            </select>
          </div>
          <div class="field">
            <label for="manage-max-devices">Maximum devices</label>
            <input id="manage-max-devices" class="input" type="number" min="1" max="1000" required>
          </div>
        </div>
        <div class="field">
          <label for="manage-expiry">License expiration</label>
          <input id="manage-expiry" class="input" type="datetime-local">
          <span class="muted small">This is the license lifetime, not the short refresh lease expiration.</span>
        </div>
        <fieldset class="field">
          <legend class="legend">Features</legend>
          <div id="manage-features" class="checkboxes"></div>
        </fieldset>
        <div class="field">
          <span class="legend">Bound devices</span>
          <div id="device-list" class="device-list"></div>
        </div>
        <div class="danger-zone">
          <div class="actions">
            <button id="reset-devices-button" class="button danger" type="button">Reset Device Slots</button>
            <button id="revoke-license-button" class="button danger" type="button">Revoke License</button>
          </div>
          <p class="muted small">Resetting slots revokes every active device binding. Revoking the license blocks future refreshes.</p>
        </div>
      </div>
      <div class="dialog-foot">
        <button class="button" data-close="manage-dialog" type="button">Cancel</button>
        <button id="manage-submit" class="button primary" type="submit">Save Changes</button>
      </div>
    </form>
  </dialog>

  <script nonce="${nonce}">
    (function () {
      "use strict";

      var FEATURES = ["automation", "stream", "script", "admin", "shell"];
      var PAGE_SIZE = 50;
      var adminToken = "";
      var licenses = [];
      var currentOffset = 0;
      var nextOffset = null;
      var totalLicenses = 0;
      var selectedLicenseId = "";

      function byId(id) { return document.getElementById(id); }

      function setNotice(message, kind) {
        var element = byId("notice");
        element.textContent = message || "";
        element.className = "notice" + (message ? " show" : "") + (kind ? " " + kind : "");
      }

      function setBusy(busy) {
        byId("dashboard-view").classList.toggle("loading", busy);
        byId("refresh-button").disabled = busy;
      }

      async function api(path, options) {
        var init = options || {};
        var headers = new Headers(init.headers || {});
        headers.set("authorization", "Bearer " + adminToken);
        if (init.body) headers.set("content-type", "application/json");
        var response = await fetch(path, Object.assign({}, init, { headers: headers }));
        var payload;
        try {
          payload = await response.json();
        } catch (_) {
          payload = { ok: false, error: "invalid_server_response" };
        }
        if (response.status === 401) {
          lockDashboard();
          throw new Error("Unauthorized. Check ADMIN_TOKEN.");
        }
        if (!response.ok || payload.ok === false) throw new Error(payload.error || "request_failed");
        return payload;
      }

      function epochFromInput(value) {
        if (!value) return 0;
        var time = new Date(value).getTime();
        return Number.isFinite(time) ? Math.floor(time / 1000) : 0;
      }

      function inputFromEpoch(epoch) {
        if (!epoch) return "";
        var date = new Date(Number(epoch) * 1000);
        var offset = date.getTimezoneOffset() * 60000;
        return new Date(date.getTime() - offset).toISOString().slice(0, 16);
      }

      function formatDate(epoch, perpetualLabel) {
        if (!epoch) return perpetualLabel || "Never";
        return new Date(Number(epoch) * 1000).toLocaleString();
      }

      function effectiveStatus(license) {
        if (license.status === "revoked") return "revoked";
        if (license.expires_at && license.expires_at <= Math.floor(Date.now() / 1000)) return "expired";
        return "active";
      }

      function addTextCell(row, value, className) {
        var cell = document.createElement("td");
        if (className) cell.className = className;
        cell.textContent = value;
        row.appendChild(cell);
        return cell;
      }

      function buildFeatureChecks(containerId, prefix) {
        var container = byId(containerId);
        container.replaceChildren();
        FEATURES.forEach(function (feature) {
          var label = document.createElement("label");
          label.className = "check";
          var input = document.createElement("input");
          input.type = "checkbox";
          input.value = feature;
          input.id = prefix + "-" + feature;
          input.checked = true;
          var text = document.createElement("span");
          text.textContent = feature;
          label.append(input, text);
          container.appendChild(label);
        });
      }

      function selectedFeatures(prefix) {
        return FEATURES.filter(function (feature) { return byId(prefix + "-" + feature).checked; });
      }

      function setSelectedFeatures(prefix, values) {
        FEATURES.forEach(function (feature) {
          byId(prefix + "-" + feature).checked = values.includes(feature);
        });
      }

      function renderRows() {
        var query = byId("search-input").value.trim().toLowerCase();
        var status = byId("status-filter").value;
        var rows = byId("license-rows");
        rows.replaceChildren();
        var visible = licenses.filter(function (license) {
          var matchesQuery = !query || license.id.toLowerCase().includes(query);
          var matchesStatus = status === "all" || effectiveStatus(license) === status;
          return matchesQuery && matchesStatus;
        });

        visible.forEach(function (license) {
          var row = document.createElement("tr");
          addTextCell(row, license.id, "id-cell");

          var statusCell = document.createElement("td");
          var state = effectiveStatus(license);
          var badge = document.createElement("span");
          badge.className = "badge " + state;
          badge.textContent = state.charAt(0).toUpperCase() + state.slice(1);
          statusCell.appendChild(badge);
          row.appendChild(statusCell);

          addTextCell(row, formatDate(license.expires_at, "No expiration"), "license-expiry");
          addTextCell(row, String(license.active_devices) + " / " + String(license.max_devices));

          var featureCell = document.createElement("td");
          featureCell.className = "hide-mobile";
          var featureWrap = document.createElement("div");
          featureWrap.className = "features";
          license.features.forEach(function (feature) {
            var tag = document.createElement("span");
            tag.className = "tag";
            tag.textContent = feature;
            featureWrap.appendChild(tag);
          });
          featureCell.appendChild(featureWrap);
          row.appendChild(featureCell);

          addTextCell(row, formatDate(license.updated_at), "hide-mobile");
          var actionCell = document.createElement("td");
          var manage = document.createElement("button");
          manage.className = "button quiet";
          manage.type = "button";
          manage.textContent = "Manage";
          manage.addEventListener("click", function () { openManage(license.id); });
          actionCell.appendChild(manage);
          row.appendChild(actionCell);
          rows.appendChild(row);
        });

        byId("empty-state").classList.toggle("hidden", visible.length !== 0);
        byId("result-count").textContent = String(visible.length) + " shown";
        byId("page-label").textContent = totalLicenses === 0
          ? "No licenses"
          : String(currentOffset + 1) + "-" + String(currentOffset + licenses.length) + " of " + String(totalLicenses);
        byId("previous-button").disabled = currentOffset === 0;
        byId("next-button").disabled = nextOffset === null;
      }

      async function loadLicenses(offset) {
        setBusy(true);
        setNotice("");
        try {
          var payload = await api("/v1/admin/licenses?limit=" + PAGE_SIZE + "&offset=" + offset);
          licenses = payload.licenses || [];
          currentOffset = payload.offset || 0;
          nextOffset = payload.next_offset;
          totalLicenses = payload.total || 0;
          var summary = payload.summary || {};
          byId("stat-total").textContent = String(summary.total || totalLicenses);
          byId("stat-active").textContent = String(summary.active || 0);
          byId("stat-revoked").textContent = String(summary.revoked || 0);
          byId("stat-expired").textContent = String(summary.expired || 0);
          byId("stat-devices").textContent = String(summary.active_devices || 0);
          renderRows();
        } catch (error) {
          setNotice(error.message, "error");
        } finally {
          setBusy(false);
        }
      }

      function unlockDashboard() {
        byId("auth-view").classList.add("hidden");
        byId("dashboard-view").classList.remove("hidden");
        byId("top-actions").classList.remove("hidden");
      }

      function lockDashboard() {
        adminToken = "";
        licenses = [];
        selectedLicenseId = "";
        byId("admin-token").value = "";
        byId("dashboard-view").classList.add("hidden");
        byId("top-actions").classList.add("hidden");
        byId("auth-view").classList.remove("hidden");
      }

      function generateLicenseKey() {
        var bytes = new Uint8Array(12);
        crypto.getRandomValues(bytes);
        var alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        var groups = [];
        for (var group = 0; group < 3; group++) {
          var value = "";
          for (var index = 0; index < 4; index++) value += alphabet[bytes[group * 4 + index] % alphabet.length];
          groups.push(value);
        }
        return "TLINK-" + groups.join("-");
      }

      function openCreate() {
        byId("create-form").reset();
        byId("create-max-devices").value = "1";
        byId("create-key").value = generateLicenseKey();
        setSelectedFeatures("create-feature", FEATURES);
        byId("created-key-result").classList.add("hidden");
        byId("create-submit").disabled = false;
        byId("create-dialog").showModal();
      }

      async function copyCreatedKey() {
        var input = byId("created-key");
        try {
          await navigator.clipboard.writeText(input.value);
          setNotice("License key copied.", "success");
        } catch (_) {
          input.focus();
          input.select();
          setNotice("Select and copy the highlighted license key.", "success");
        }
      }

      async function createLicense(event) {
        event.preventDefault();
        var features = selectedFeatures("create-feature");
        if (features.length === 0) {
          setNotice("Select at least one feature.", "error");
          return;
        }
        var button = byId("create-submit");
        button.disabled = true;
        try {
          var payload = await api("/v1/admin/licenses", {
            method: "POST",
            body: JSON.stringify({
              license_key: byId("create-key").value,
              max_devices: Number(byId("create-max-devices").value),
              expires_at: epochFromInput(byId("create-expiry").value),
              features: features
            })
          });
          byId("created-key").value = payload.license_key;
          byId("created-key-result").classList.remove("hidden");
          setNotice("License created successfully.", "success");
          await loadLicenses(0);
        } catch (error) {
          setNotice(error.message, "error");
          button.disabled = false;
        }
      }

      function renderDevices(devices) {
        var list = byId("device-list");
        list.replaceChildren();
        if (!devices.length) {
          var empty = document.createElement("div");
          empty.className = "empty";
          empty.textContent = "No devices have activated this license.";
          list.appendChild(empty);
          return;
        }
        devices.forEach(function (device) {
          var row = document.createElement("div");
          row.className = "device";
          var identity = document.createElement("div");
          var id = document.createElement("div");
          id.className = "device-id";
          id.title = device.id;
          id.textContent = device.id;
          var hash = document.createElement("div");
          hash.className = "muted small device-id";
          hash.title = device.device_key_hash;
          hash.textContent = "Key " + device.device_key_hash.slice(0, 14) + "...";
          identity.append(id, hash);

          var seen = document.createElement("span");
          seen.className = "muted small device-seen";
          seen.textContent = "Seen " + formatDate(device.last_seen_at);

          var control = document.createElement("div");
          if (device.status === "active") {
            var revoke = document.createElement("button");
            revoke.type = "button";
            revoke.className = "button danger quiet";
            revoke.textContent = "Revoke";
            revoke.addEventListener("click", function () { revokeDevice(device.id); });
            control.appendChild(revoke);
          } else {
            var badge = document.createElement("span");
            badge.className = "badge revoked";
            badge.textContent = "Revoked";
            control.appendChild(badge);
          }
          row.append(identity, seen, control);
          list.appendChild(row);
        });
      }

      async function openManage(id) {
        selectedLicenseId = id;
        setNotice("");
        try {
          var payload = await api("/v1/admin/license?id=" + encodeURIComponent(id));
          var license = payload.license;
          byId("manage-id").textContent = license.id;
          byId("manage-status").value = license.status;
          byId("manage-max-devices").value = String(license.max_devices);
          byId("manage-expiry").value = inputFromEpoch(license.expires_at);
          setSelectedFeatures("manage-feature", license.features);
          renderDevices(payload.devices || []);
          byId("manage-dialog").showModal();
        } catch (error) {
          setNotice(error.message, "error");
        }
      }

      async function saveLicense(event) {
        event.preventDefault();
        var features = selectedFeatures("manage-feature");
        if (features.length === 0) {
          setNotice("Select at least one feature.", "error");
          return;
        }
        var button = byId("manage-submit");
        button.disabled = true;
        try {
          await api("/v1/admin/update", {
            method: "POST",
            body: JSON.stringify({
              license_id: selectedLicenseId,
              status: byId("manage-status").value,
              max_devices: Number(byId("manage-max-devices").value),
              expires_at: epochFromInput(byId("manage-expiry").value),
              features: features
            })
          });
          byId("manage-dialog").close();
          setNotice("License updated.", "success");
          await loadLicenses(currentOffset);
        } catch (error) {
          setNotice(error.message, "error");
        } finally {
          button.disabled = false;
        }
      }

      async function resetDevices() {
        if (!confirm("Revoke every active device binding for this license?")) return;
        try {
          var payload = await api("/v1/admin/reset-devices", {
            method: "POST",
            body: JSON.stringify({ license_id: selectedLicenseId })
          });
          setNotice("Reset " + String(payload.reset_devices || 0) + " active device slot(s).", "success");
          byId("manage-dialog").close();
          await openManage(selectedLicenseId);
          await loadLicenses(currentOffset);
        } catch (error) {
          setNotice(error.message, "error");
        }
      }

      async function revokeLicense() {
        if (!confirm("Revoke this license? Devices will fail on their next refresh.")) return;
        try {
          await api("/v1/admin/revoke", {
            method: "POST",
            body: JSON.stringify({ license_id: selectedLicenseId })
          });
          byId("manage-dialog").close();
          setNotice("License revoked.", "success");
          await loadLicenses(currentOffset);
        } catch (error) {
          setNotice(error.message, "error");
        }
      }

      async function revokeDevice(deviceId) {
        if (!confirm("Revoke this device binding?")) return;
        try {
          await api("/v1/admin/revoke-device", {
            method: "POST",
            body: JSON.stringify({ license_id: selectedLicenseId, device_id: deviceId })
          });
          setNotice("Device binding revoked.", "success");
          byId("manage-dialog").close();
          await openManage(selectedLicenseId);
          await loadLicenses(currentOffset);
        } catch (error) {
          setNotice(error.message, "error");
        }
      }

      buildFeatureChecks("create-features", "create-feature");
      buildFeatureChecks("manage-features", "manage-feature");

      byId("auth-form").addEventListener("submit", async function (event) {
        event.preventDefault();
        adminToken = byId("admin-token").value;
        unlockDashboard();
        await loadLicenses(0);
        if (!adminToken) lockDashboard();
      });
      byId("refresh-button").addEventListener("click", function () { loadLicenses(currentOffset); });
      byId("new-button").addEventListener("click", openCreate);
      byId("lock-button").addEventListener("click", function () { lockDashboard(); setNotice("Admin token cleared."); });
      byId("search-input").addEventListener("input", renderRows);
      byId("status-filter").addEventListener("change", renderRows);
      byId("previous-button").addEventListener("click", function () { loadLicenses(Math.max(0, currentOffset - PAGE_SIZE)); });
      byId("next-button").addEventListener("click", function () { if (nextOffset !== null) loadLicenses(nextOffset); });
      byId("generate-key-button").addEventListener("click", function () { byId("create-key").value = generateLicenseKey(); });
      byId("copy-key-button").addEventListener("click", copyCreatedKey);
      byId("create-form").addEventListener("submit", createLicense);
      byId("manage-form").addEventListener("submit", saveLicense);
      byId("reset-devices-button").addEventListener("click", resetDevices);
      byId("revoke-license-button").addEventListener("click", revokeLicense);
      document.querySelectorAll("[data-close]").forEach(function (button) {
        button.addEventListener("click", function () { byId(button.dataset.close).close(); });
      });

      if (location.protocol !== "https:" && location.hostname !== "localhost" && location.hostname !== "127.0.0.1") {
        setNotice("Use HTTPS before entering ADMIN_TOKEN.", "error");
      }
    })();
  <\/script>
</body>
</html>`;
}
__name(renderAdminDashboard, "renderAdminDashboard");

// src/index.js
var encoder = new TextEncoder();
var decoder = new TextDecoder();
var LICENSE_CONTRACT_VERSION = 1;
var MAX_BODY_BYTES = 16 * 1024;
var MAX_LICENSE_KEY_LENGTH = 128;
var ALLOWED_FEATURES = /* @__PURE__ */ new Set(["automation", "stream", "script", "admin", "shell"]);
var DEFAULT_FEATURES = ["automation", "stream", "script", "admin", "shell"];
var RequestError = class extends Error {
  static {
    __name(this, "RequestError");
  }
  constructor(status, code) {
    super(code);
    this.name = "RequestError";
    this.status = status;
    this.code = code;
  }
};
function jsonResponse(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "access-control-allow-origin": "*",
      "access-control-allow-headers": "authorization, content-type",
      "access-control-allow-methods": "GET, POST, OPTIONS"
    }
  });
}
__name(jsonResponse, "jsonResponse");
function htmlResponse(html, nonce) {
  return new Response(html, {
    status: 200,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "content-security-policy": `default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; frame-ancestors 'none'; form-action 'none'`,
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      "x-frame-options": "DENY"
    }
  });
}
__name(htmlResponse, "htmlResponse");
function errorResponse(code, status, details = {}) {
  return jsonResponse({ ok: false, error: code, ...details }, status);
}
__name(errorResponse, "errorResponse");
function base64UrlEncode(input) {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
__name(base64UrlEncode, "base64UrlEncode");
function base64UrlDecode(value) {
  if (typeof value !== "string" || value.length === 0 || value.length > 4096 || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error("invalid_base64url");
  }
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - normalized.length % 4) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
__name(base64UrlDecode, "base64UrlDecode");
function randomToken(bytes = 32) {
  const value = new Uint8Array(bytes);
  crypto.getRandomValues(value);
  return base64UrlEncode(value);
}
__name(randomToken, "randomToken");
async function sha256Base64Url(value) {
  const bytes = typeof value === "string" ? encoder.encode(value) : value;
  return base64UrlEncode(await crypto.subtle.digest("SHA-256", bytes));
}
__name(sha256Base64Url, "sha256Base64Url");
function normalizeLicenseKey(value) {
  if (typeof value !== "string") return "";
  return value.trim().toUpperCase().replace(/\s+/g, "");
}
__name(normalizeLicenseKey, "normalizeLicenseKey");
function validatedLicenseKey(value) {
  const key = normalizeLicenseKey(value);
  if (key.length < 8 || key.length > MAX_LICENSE_KEY_LENGTH || !/^[A-Z0-9_-]+$/.test(key)) {
    throw new RequestError(400, "invalid_license_key_format");
  }
  return key;
}
__name(validatedLicenseKey, "validatedLicenseKey");
function validatedIdentifier(value) {
  if (value === void 0 || value === null || value === "") return crypto.randomUUID();
  if (typeof value !== "string" || value.length > 64 || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new RequestError(400, "invalid_license_id");
  }
  return value;
}
__name(validatedIdentifier, "validatedIdentifier");
function validatedExistingIdentifier(value, name = "identifier") {
  if (typeof value !== "string" || value.length === 0 || value.length > 64 || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new RequestError(400, `invalid_${name}`);
  }
  return value;
}
__name(validatedExistingIdentifier, "validatedExistingIdentifier");
function validatedInteger(value, name, minimum, maximum, fallback) {
  if (value === void 0 || value === null || value === "") return fallback;
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < minimum || number > maximum) {
    throw new RequestError(400, `invalid_${name}`);
  }
  return number;
}
__name(validatedInteger, "validatedInteger");
function validatedFeatures(value, fallback = DEFAULT_FEATURES) {
  const features = value === void 0 ? fallback : value;
  if (!Array.isArray(features) || features.length === 0 || features.length > ALLOWED_FEATURES.size) {
    throw new RequestError(400, "invalid_features");
  }
  const normalized = [];
  for (const feature of features) {
    if (typeof feature !== "string" || !ALLOWED_FEATURES.has(feature) || normalized.includes(feature)) {
      throw new RequestError(400, "invalid_features");
    }
    normalized.push(feature);
  }
  return normalized;
}
__name(validatedFeatures, "validatedFeatures");
function validatedStatus(value, fallback = "active") {
  const status = value === void 0 ? fallback : value;
  if (status !== "active" && status !== "revoked") throw new RequestError(400, "invalid_status");
  return status;
}
__name(validatedStatus, "validatedStatus");
function database(env) {
  const binding = env.DB || env.tlinkauto_license;
  if (!binding || typeof binding.prepare !== "function") {
    throw new Error("d1_binding_missing expected=DB legacy=tlinkauto_license");
  }
  return binding;
}
__name(database, "database");
function trimInteger(bytes) {
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0) start++;
  let out = bytes.slice(start);
  if (out[0] & 128) {
    const prefixed = new Uint8Array(out.length + 1);
    prefixed.set(out, 1);
    out = prefixed;
  }
  return out;
}
__name(trimInteger, "trimInteger");
function rawSignatureToDer(rawValue) {
  const raw = new Uint8Array(rawValue);
  if (raw.length !== 64) throw new Error("invalid_raw_ecdsa_signature");
  const r = trimInteger(raw.slice(0, 32));
  const s = trimInteger(raw.slice(32, 64));
  const bodyLength = 2 + r.length + 2 + s.length;
  const der = new Uint8Array(2 + bodyLength);
  let offset = 0;
  der[offset++] = 48;
  der[offset++] = bodyLength;
  der[offset++] = 2;
  der[offset++] = r.length;
  der.set(r, offset);
  offset += r.length;
  der[offset++] = 2;
  der[offset++] = s.length;
  der.set(s, offset);
  return der;
}
__name(rawSignatureToDer, "rawSignatureToDer");
function derSignatureToRaw(derValue) {
  const der = new Uint8Array(derValue);
  if (der.length < 8 || der[0] !== 48 || der[1] !== der.length - 2) {
    throw new Error("invalid_der_ecdsa_signature");
  }
  let offset = 2;
  if (der[offset++] !== 2) throw new Error("invalid_der_r");
  const rLength = der[offset++];
  if (rLength < 1 || rLength > 33 || offset + rLength > der.length) throw new Error("invalid_der_r_length");
  let r = der.slice(offset, offset + rLength);
  offset += rLength;
  if (der[offset++] !== 2) throw new Error("invalid_der_s");
  const sLength = der[offset++];
  if (sLength < 1 || sLength > 33 || offset + sLength !== der.length) throw new Error("invalid_der_s_length");
  let s = der.slice(offset, offset + sLength);
  if (r.length === 33 && r[0] === 0) r = r.slice(1);
  if (s.length === 33 && s[0] === 0) s = s.slice(1);
  if (r.length > 32 || s.length > 32) throw new Error("invalid_der_component_size");
  const raw = new Uint8Array(64);
  raw.set(r, 32 - r.length);
  raw.set(s, 64 - s.length);
  return raw;
}
__name(derSignatureToRaw, "derSignatureToRaw");
function validatePublicJwk(value) {
  if (!value || typeof value !== "object" || value.kty !== "EC" || value.crv !== "P-256") {
    throw new RequestError(400, "invalid_device_public_key");
  }
  let x;
  let y;
  try {
    x = base64UrlDecode(value.x);
    y = base64UrlDecode(value.y);
  } catch {
    throw new RequestError(400, "invalid_device_public_key");
  }
  if (x.length !== 32 || y.length !== 32) throw new RequestError(400, "invalid_device_public_key_size");
  return { kty: "EC", crv: "P-256", x: value.x, y: value.y, ext: true };
}
__name(validatePublicJwk, "validatePublicJwk");
async function deviceKeyHash(publicJwk) {
  const jwk = validatePublicJwk(publicJwk);
  const point = new Uint8Array(65);
  point[0] = 4;
  point.set(base64UrlDecode(jwk.x), 1);
  point.set(base64UrlDecode(jwk.y), 33);
  return sha256Base64Url(point);
}
__name(deviceKeyHash, "deviceKeyHash");
async function signingKeys(env) {
  let privateJwk;
  try {
    privateJwk = JSON.parse(env.LICENSE_SIGNING_PRIVATE_JWK || "");
  } catch {
    throw new Error("license_signing_key_invalid");
  }
  const publicJwk = { ...privateJwk };
  delete publicJwk.d;
  publicJwk.key_ops = ["verify"];
  const privateKey = await crypto.subtle.importKey(
    "jwk",
    privateJwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
  const publicKey = await crypto.subtle.importKey(
    "jwk",
    publicJwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"]
  );
  return { privateKey, publicKey, publicJwk };
}
__name(signingKeys, "signingKeys");
async function signPayload(env, payload) {
  const payloadBytes = encoder.encode(JSON.stringify(payload));
  const { privateKey } = await signingKeys(env);
  const rawSignature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    payloadBytes
  );
  return {
    version: 1,
    key_id: env.LICENSE_KEY_ID || "tlinkauto-test-2026-01",
    payload: base64UrlEncode(payloadBytes),
    signature: base64UrlEncode(rawSignatureToDer(rawSignature))
  };
}
__name(signPayload, "signPayload");
function validateLeasePayload(payload) {
  const contractVersion = payload?.license_contract_version ?? 1;
  if (!payload || payload.version !== 1 || payload.product !== "tlinkauto" || contractVersion !== LICENSE_CONTRACT_VERSION) {
    throw new Error("invalid_lease_contract");
  }
  if (typeof payload.license_id !== "string" || typeof payload.device_id !== "string" || typeof payload.device_key_hash !== "string" || !Array.isArray(payload.features)) {
    throw new Error("invalid_lease_payload");
  }
  validatedFeatures(payload.features);
  return { ...payload, license_contract_version: contractVersion };
}
__name(validateLeasePayload, "validateLeasePayload");
async function verifyLease(env, lease) {
  const expectedKeyId = env.LICENSE_KEY_ID || "tlinkauto-test-2026-01";
  if (!lease || lease.version !== 1 || lease.key_id !== expectedKeyId || !lease.payload || !lease.signature) {
    throw new Error("invalid_lease");
  }
  const payloadBytes = base64UrlDecode(lease.payload);
  const signatureRaw = derSignatureToRaw(base64UrlDecode(lease.signature));
  const { publicKey } = await signingKeys(env);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    signatureRaw,
    payloadBytes
  );
  if (!valid) throw new Error("invalid_lease_signature");
  return validateLeasePayload(JSON.parse(decoder.decode(payloadBytes)));
}
__name(verifyLease, "verifyLease");
async function readJson(request) {
  const declaredLength = Number(request.headers.get("content-length") || 0);
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    throw new RequestError(413, "request_body_too_large");
  }
  const text = await request.text();
  if (encoder.encode(text).length > MAX_BODY_BYTES) throw new RequestError(413, "request_body_too_large");
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    throw new RequestError(400, "invalid_json");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new RequestError(400, "invalid_json_object");
  return value;
}
__name(readJson, "readJson");
async function loadLicense(env, normalizedKey) {
  const keyHash = await sha256Base64Url(encoder.encode(normalizedKey));
  return database(env).prepare("SELECT * FROM licenses WHERE key_hash = ?").bind(keyHash).first();
}
__name(loadLicense, "loadLicense");
function licenseUsable(license, now) {
  return license && license.status === "active" && (!license.expires_at || license.expires_at > now);
}
__name(licenseUsable, "licenseUsable");
function featuresFromLicense(license) {
  let features;
  try {
    features = JSON.parse(license.features_json || "[]");
  } catch {
    throw new Error("stored_license_features_invalid");
  }
  return validatedFeatures(features);
}
__name(featuresFromLicense, "featuresFromLicense");
async function issueLease(env, license, device) {
  const now = Math.floor(Date.now() / 1e3);
  const leaseSeconds = Math.max(300, Number(env.LEASE_SECONDS || 86400));
  const graceSeconds = Math.max(leaseSeconds, Number(env.OFFLINE_GRACE_SECONDS || 259200));
  const licenseExpiresAt = Math.max(0, Number(license.expires_at || 0));
  const requestedLeaseExpiresAt = now + leaseSeconds;
  const requestedOfflineUntil = now + graceSeconds;
  const leaseExpiresAt = licenseExpiresAt > 0 ? Math.min(requestedLeaseExpiresAt, licenseExpiresAt) : requestedLeaseExpiresAt;
  const offlineUntil = licenseExpiresAt > 0 ? Math.min(requestedOfflineUntil, licenseExpiresAt) : requestedOfflineUntil;
  return signPayload(env, {
    version: 1,
    license_contract_version: LICENSE_CONTRACT_VERSION,
    product: "tlinkauto",
    token_id: crypto.randomUUID(),
    license_id: license.id,
    device_id: device.id,
    device_key_hash: device.device_key_hash,
    issued_at: now,
    not_before: now - 30,
    expires_at: leaseExpiresAt,
    offline_until: offlineUntil,
    license_expires_at: licenseExpiresAt,
    lease_policy_seconds: leaseSeconds,
    offline_grace_policy_seconds: graceSeconds,
    renewal_mode: "server_refresh_until_license_expiry",
    features: featuresFromLicense(license)
  });
}
__name(issueLease, "issueLease");
async function cleanupExpiredChallenges(env, now) {
  await database(env).prepare("DELETE FROM activation_challenges WHERE expires_at < ?").bind(now).run();
}
__name(cleanupExpiredChallenges, "cleanupExpiredChallenges");
async function handleChallenge(request, env) {
  const body = await readJson(request);
  const key = validatedLicenseKey(body.license_key);
  const publicJwk = validatePublicJwk(body.device_public_key);
  const license = await loadLicense(env, key);
  const now = Math.floor(Date.now() / 1e3);
  if (!licenseUsable(license, now)) return errorResponse("invalid_license", 403);
  await cleanupExpiredChallenges(env, now);
  const id = crypto.randomUUID();
  const challenge = randomToken(32);
  const keyHash = await deviceKeyHash(publicJwk);
  await database(env).prepare(
    "INSERT INTO activation_challenges (id, license_id, device_key_hash, challenge, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)"
  ).bind(id, license.id, keyHash, challenge, now + 300, now).run();
  return jsonResponse({ ok: true, license_contract_version: LICENSE_CONTRACT_VERSION, challenge_id: id, challenge, expires_at: now + 300 });
}
__name(handleChallenge, "handleChallenge");
async function verifyDeviceSignature(publicJwk, signature, message) {
  let signatureRaw;
  try {
    signatureRaw = derSignatureToRaw(base64UrlDecode(signature));
  } catch {
    return false;
  }
  const deviceKey = await crypto.subtle.importKey(
    "jwk",
    publicJwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"]
  );
  return crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    deviceKey,
    signatureRaw,
    encoder.encode(message)
  );
}
__name(verifyDeviceSignature, "verifyDeviceSignature");
async function activeDeviceCount(env, licenseId) {
  const row = await database(env).prepare(
    "SELECT COUNT(*) AS count FROM devices WHERE license_id = ? AND status = 'active'"
  ).bind(licenseId).first();
  return Number(row?.count || 0);
}
__name(activeDeviceCount, "activeDeviceCount");
async function handleActivate(request, env) {
  const body = await readJson(request);
  const key = validatedLicenseKey(body.license_key);
  const publicJwk = validatePublicJwk(body.device_public_key);
  const challengeId = typeof body.challenge_id === "string" && body.challenge_id.length <= 64 ? body.challenge_id : "";
  const signature = typeof body.signature === "string" && body.signature.length <= 512 ? body.signature : "";
  if (!challengeId || !signature) throw new RequestError(400, "invalid_activation_request");
  const deviceHash = await deviceKeyHash(publicJwk);
  const license = await loadLicense(env, key);
  const now = Math.floor(Date.now() / 1e3);
  if (!licenseUsable(license, now)) return errorResponse("invalid_license", 403);
  await cleanupExpiredChallenges(env, now);
  const challengeRow = await database(env).prepare(
    "SELECT * FROM activation_challenges WHERE id = ? AND license_id = ?"
  ).bind(challengeId, license.id).first();
  if (!challengeRow || challengeRow.expires_at < now || challengeRow.device_key_hash !== deviceHash) {
    return errorResponse("invalid_or_expired_challenge", 403);
  }
  const proofValid = await verifyDeviceSignature(publicJwk, signature, challengeRow.challenge);
  if (!proofValid) return errorResponse("invalid_device_signature", 403);
  const consume = await database(env).prepare(
    "DELETE FROM activation_challenges WHERE id = ? AND license_id = ? AND device_key_hash = ? AND expires_at >= ?"
  ).bind(challengeRow.id, license.id, deviceHash, now).run();
  if (Number(consume.meta?.changes || 0) !== 1) return errorResponse("challenge_already_consumed", 409);
  let device = await database(env).prepare(
    "SELECT * FROM devices WHERE license_id = ? AND device_key_hash = ?"
  ).bind(license.id, deviceHash).first();
  if (!device) {
    const activeDevices = await activeDeviceCount(env, license.id);
    const maxDevices = Number(license.max_devices || 1);
    if (activeDevices >= maxDevices) {
      return errorResponse("device_limit_reached", 409, {
        recovery: "deactivate_old_device_or_admin_reset",
        active_devices: activeDevices,
        max_devices: maxDevices
      });
    }
    const deviceId = crypto.randomUUID();
    await database(env).prepare(
      "INSERT INTO devices (id, license_id, device_key_hash, public_jwk, status, created_at, last_seen_at) VALUES (?, ?, ?, ?, 'active', ?, ?)"
    ).bind(deviceId, license.id, deviceHash, JSON.stringify(publicJwk), now, now).run();
    device = await database(env).prepare("SELECT * FROM devices WHERE id = ?").bind(deviceId).first();
  } else if (device.status === "active") {
    await database(env).prepare("UPDATE devices SET last_seen_at = ?, public_jwk = ? WHERE id = ?").bind(now, JSON.stringify(publicJwk), device.id).run();
  } else {
    const activeDevices = await activeDeviceCount(env, license.id);
    const maxDevices = Number(license.max_devices || 1);
    if (activeDevices >= maxDevices) {
      return errorResponse("device_limit_reached", 409, {
        recovery: "deactivate_old_device_or_admin_reset",
        active_devices: activeDevices,
        max_devices: maxDevices
      });
    }
    await database(env).prepare("UPDATE devices SET status = 'active', public_jwk = ?, last_seen_at = ? WHERE id = ?").bind(JSON.stringify(publicJwk), now, device.id).run();
  }
  device = await database(env).prepare("SELECT * FROM devices WHERE id = ?").bind(device.id).first();
  return jsonResponse({ ok: true, license_contract_version: LICENSE_CONTRACT_VERSION, lease: await issueLease(env, license, device) });
}
__name(handleActivate, "handleActivate");
async function authenticatedDeviceRequest(body, env) {
  if (!body.lease || typeof body.device_signature !== "string" || body.device_signature.length > 512) {
    throw new RequestError(400, "invalid_device_request");
  }
  let payload;
  try {
    payload = await verifyLease(env, body.lease);
  } catch (error) {
    throw new RequestError(403, error.message || "invalid_lease");
  }
  const now = Math.floor(Date.now() / 1e3);
  const license = await database(env).prepare("SELECT * FROM licenses WHERE id = ?").bind(payload.license_id).first();
  const device = await database(env).prepare("SELECT * FROM devices WHERE id = ?").bind(payload.device_id).first();
  if (!licenseUsable(license, now)) throw new RequestError(403, "license_revoked_or_expired");
  if (!device || device.status !== "active" || device.license_id !== license.id || device.device_key_hash !== payload.device_key_hash) {
    throw new RequestError(403, "device_revoked");
  }
  let publicJwk;
  try {
    publicJwk = validatePublicJwk(JSON.parse(device.public_jwk || "{}"));
  } catch {
    throw new RequestError(403, "device_public_key_invalid");
  }
  const proofValid = await verifyDeviceSignature(publicJwk, body.device_signature, body.lease.payload);
  if (!proofValid) throw new RequestError(403, "invalid_device_signature");
  return { payload, license, device, now };
}
__name(authenticatedDeviceRequest, "authenticatedDeviceRequest");
async function handleRefresh(request, env) {
  const body = await readJson(request);
  const context = await authenticatedDeviceRequest(body, env);
  await database(env).prepare("UPDATE devices SET last_seen_at = ? WHERE id = ?").bind(context.now, context.device.id).run();
  return jsonResponse({
    ok: true,
    license_contract_version: LICENSE_CONTRACT_VERSION,
    lease: await issueLease(env, context.license, context.device)
  });
}
__name(handleRefresh, "handleRefresh");
async function handleDeactivate(request, env) {
  const body = await readJson(request);
  const context = await authenticatedDeviceRequest(body, env);
  await database(env).prepare("UPDATE devices SET status = 'revoked', last_seen_at = ? WHERE id = ?").bind(context.now, context.device.id).run();
  return jsonResponse({ ok: true, license_contract_version: LICENSE_CONTRACT_VERSION, device_id: context.device.id, status: "revoked" });
}
__name(handleDeactivate, "handleDeactivate");
function requireAdmin(request, env) {
  const value = request.headers.get("authorization") || "";
  return Boolean(env.ADMIN_TOKEN) && value === `Bearer ${env.ADMIN_TOKEN}`;
}
__name(requireAdmin, "requireAdmin");
async function handleAdminCreateLicense(request, env) {
  if (!requireAdmin(request, env)) return errorResponse("unauthorized", 401);
  const body = await readJson(request);
  const key = validatedLicenseKey(body.license_key);
  if (await loadLicense(env, key)) return errorResponse("license_exists", 409);
  const now = Math.floor(Date.now() / 1e3);
  const id = validatedIdentifier(body.id);
  const keyHash = await sha256Base64Url(encoder.encode(key));
  const features = validatedFeatures(body.features);
  const maxDevices = validatedInteger(body.max_devices, "max_devices", 1, 1e3, 1);
  const expiresAt = validatedInteger(body.expires_at, "expires_at", 0, 4102444800, 0);
  await database(env).prepare(
    "INSERT INTO licenses (id, key_hash, status, max_devices, features_json, expires_at, created_at, updated_at) VALUES (?, ?, 'active', ?, ?, ?, ?, ?)"
  ).bind(id, keyHash, maxDevices, JSON.stringify(features), expiresAt, now, now).run();
  return jsonResponse({ ok: true, id, license_key: key, status: "active", max_devices: maxDevices, expires_at: expiresAt, features });
}
__name(handleAdminCreateLicense, "handleAdminCreateLicense");
async function licenseForAdminBody(body, env) {
  let key = "";
  let license = null;
  if (body.license_id !== void 0) {
    const id = validatedExistingIdentifier(body.license_id, "license_id");
    license = await database(env).prepare("SELECT * FROM licenses WHERE id = ?").bind(id).first();
  } else {
    key = validatedLicenseKey(body.license_key);
    license = await loadLicense(env, key);
  }
  if (!license) throw new RequestError(404, "not_found");
  return { key, license };
}
__name(licenseForAdminBody, "licenseForAdminBody");
function adminLicenseRecord(license, activeDevices, totalDevices) {
  return {
    id: license.id,
    status: license.status,
    max_devices: Number(license.max_devices || 1),
    features: featuresFromLicense(license),
    expires_at: Number(license.expires_at || 0),
    created_at: Number(license.created_at || 0),
    updated_at: Number(license.updated_at || 0),
    active_devices: Number(activeDevices || 0),
    total_devices: Number(totalDevices || 0)
  };
}
__name(adminLicenseRecord, "adminLicenseRecord");
async function handleAdminListLicenses(request, env) {
  if (!requireAdmin(request, env)) return errorResponse("unauthorized", 401);
  const url = new URL(request.url);
  const limit = validatedInteger(url.searchParams.get("limit"), "limit", 1, 100, 50);
  const offset = validatedInteger(url.searchParams.get("offset"), "offset", 0, 1e6, 0);
  const result = await database(env).prepare(
    "SELECT id, status, max_devices, features_json, expires_at, created_at, updated_at, (SELECT COUNT(*) FROM devices WHERE license_id = licenses.id AND status = 'active') AS active_devices, (SELECT COUNT(*) FROM devices WHERE license_id = licenses.id) AS total_devices FROM licenses ORDER BY updated_at DESC LIMIT ? OFFSET ?"
  ).bind(limit + 1, offset).all();
  const rows = Array.isArray(result.results) ? result.results : [];
  const visible = rows.slice(0, limit);
  const licenses = visible.map((license) => adminLicenseRecord(license, license.active_devices, license.total_devices));
  const now = Math.floor(Date.now() / 1e3);
  const summaryRow = await database(env).prepare(
    "SELECT COUNT(*) AS total, SUM(CASE WHEN status = 'active' AND (expires_at = 0 OR expires_at > ?) THEN 1 ELSE 0 END) AS active, SUM(CASE WHEN status = 'revoked' THEN 1 ELSE 0 END) AS revoked, SUM(CASE WHEN status = 'active' AND expires_at > 0 AND expires_at <= ? THEN 1 ELSE 0 END) AS expired FROM licenses"
  ).bind(now, now).first();
  const activeDevicesRow = await database(env).prepare(
    "SELECT COUNT(*) AS count FROM devices WHERE status = 'active'"
  ).first();
  const summary = {
    total: Number(summaryRow?.total || 0),
    active: Number(summaryRow?.active || 0),
    revoked: Number(summaryRow?.revoked || 0),
    expired: Number(summaryRow?.expired || 0),
    active_devices: Number(activeDevicesRow?.count || 0)
  };
  return jsonResponse({
    ok: true,
    licenses,
    total: summary.total,
    summary,
    offset,
    next_offset: rows.length > limit ? offset + limit : null
  });
}
__name(handleAdminListLicenses, "handleAdminListLicenses");
async function handleAdminLicenseDetail(request, env) {
  if (!requireAdmin(request, env)) return errorResponse("unauthorized", 401);
  const url = new URL(request.url);
  const id = validatedExistingIdentifier(url.searchParams.get("id"), "license_id");
  const license = await database(env).prepare("SELECT * FROM licenses WHERE id = ?").bind(id).first();
  if (!license) throw new RequestError(404, "not_found");
  const devicesResult = await database(env).prepare(
    "SELECT id, device_key_hash, status, created_at, last_seen_at FROM devices WHERE license_id = ? ORDER BY last_seen_at DESC"
  ).bind(id).all();
  const devices = (Array.isArray(devicesResult.results) ? devicesResult.results : []).map((device) => ({
    id: device.id,
    device_key_hash: device.device_key_hash,
    status: device.status,
    created_at: Number(device.created_at || 0),
    last_seen_at: Number(device.last_seen_at || 0)
  }));
  const activeDevices = devices.filter((device) => device.status === "active").length;
  return jsonResponse({
    ok: true,
    license: adminLicenseRecord(license, activeDevices, devices.length),
    devices
  });
}
__name(handleAdminLicenseDetail, "handleAdminLicenseDetail");
async function handleAdminRevokeDevice(request, env) {
  if (!requireAdmin(request, env)) return errorResponse("unauthorized", 401);
  const body = await readJson(request);
  const licenseId = validatedExistingIdentifier(body.license_id, "license_id");
  const deviceId = validatedExistingIdentifier(body.device_id, "device_id");
  const device = await database(env).prepare("SELECT * FROM devices WHERE id = ?").bind(deviceId).first();
  if (!device || device.license_id !== licenseId) throw new RequestError(404, "not_found");
  const now = Math.floor(Date.now() / 1e3);
  await database(env).prepare("UPDATE devices SET status = 'revoked', last_seen_at = ? WHERE id = ?").bind(now, device.id).run();
  return jsonResponse({ ok: true, license_id: licenseId, device_id: device.id, status: "revoked" });
}
__name(handleAdminRevokeDevice, "handleAdminRevokeDevice");
async function handleAdminUpdate(request, env) {
  if (!requireAdmin(request, env)) return errorResponse("unauthorized", 401);
  const body = await readJson(request);
  const { license } = await licenseForAdminBody(body, env);
  const hasUpdate = ["status", "max_devices", "expires_at", "features"].some((key) => Object.hasOwn(body, key));
  if (!hasUpdate) throw new RequestError(400, "no_license_updates");
  const status = validatedStatus(body.status, license.status);
  const maxDevices = validatedInteger(body.max_devices, "max_devices", 1, 1e3, Number(license.max_devices));
  const expiresAt = validatedInteger(body.expires_at, "expires_at", 0, 4102444800, Number(license.expires_at));
  const currentFeatures = featuresFromLicense(license);
  const features = validatedFeatures(body.features, currentFeatures);
  const now = Math.floor(Date.now() / 1e3);
  await database(env).prepare(
    "UPDATE licenses SET status = ?, max_devices = ?, features_json = ?, expires_at = ?, updated_at = ? WHERE id = ?"
  ).bind(status, maxDevices, JSON.stringify(features), expiresAt, now, license.id).run();
  return jsonResponse({ ok: true, id: license.id, status, max_devices: maxDevices, expires_at: expiresAt, features });
}
__name(handleAdminUpdate, "handleAdminUpdate");
async function handleAdminRevoke(request, env) {
  if (!requireAdmin(request, env)) return errorResponse("unauthorized", 401);
  const body = await readJson(request);
  const { license } = await licenseForAdminBody(body, env);
  const now = Math.floor(Date.now() / 1e3);
  await database(env).prepare("UPDATE licenses SET status = 'revoked', updated_at = ? WHERE id = ?").bind(now, license.id).run();
  return jsonResponse({ ok: true, id: license.id, status: "revoked" });
}
__name(handleAdminRevoke, "handleAdminRevoke");
async function handleAdminResetDevices(request, env) {
  if (!requireAdmin(request, env)) return errorResponse("unauthorized", 401);
  const body = await readJson(request);
  const { license } = await licenseForAdminBody(body, env);
  const now = Math.floor(Date.now() / 1e3);
  const result = await database(env).prepare(
    "UPDATE devices SET status = 'revoked', last_seen_at = ? WHERE license_id = ? AND status = 'active'"
  ).bind(now, license.id).run();
  await database(env).prepare("DELETE FROM activation_challenges WHERE license_id = ?").bind(license.id).run();
  return jsonResponse({
    ok: true,
    id: license.id,
    reset_devices: Number(result.meta?.changes || 0)
  });
}
__name(handleAdminResetDevices, "handleAdminResetDevices");
var worker = {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return jsonResponse({ ok: true });
    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/v1/health") {
        return jsonResponse({
          ok: true,
          service: "tlinkauto-license",
          license_contract_version: LICENSE_CONTRACT_VERSION,
          now: Math.floor(Date.now() / 1e3)
        });
      }
      if (request.method === "GET" && url.pathname === "/v1/public-key") {
        const { publicJwk } = await signingKeys(env);
        return jsonResponse({
          ok: true,
          license_contract_version: LICENSE_CONTRACT_VERSION,
          key_id: env.LICENSE_KEY_ID || "tlinkauto-test-2026-01",
          public_key: publicJwk
        });
      }
      if (request.method === "GET" && (url.pathname === "/admin" || url.pathname === "/admin/")) {
        const nonce = randomToken(18);
        return htmlResponse(renderAdminDashboard(nonce), nonce);
      }
      if (request.method === "POST" && url.pathname === "/v1/challenge") return await handleChallenge(request, env);
      if (request.method === "POST" && url.pathname === "/v1/activate") return await handleActivate(request, env);
      if (request.method === "POST" && url.pathname === "/v1/refresh") return await handleRefresh(request, env);
      if (request.method === "POST" && url.pathname === "/v1/deactivate") return await handleDeactivate(request, env);
      if (request.method === "POST" && url.pathname === "/v1/admin/licenses") return await handleAdminCreateLicense(request, env);
      if (request.method === "GET" && url.pathname === "/v1/admin/licenses") return await handleAdminListLicenses(request, env);
      if (request.method === "GET" && url.pathname === "/v1/admin/license") return await handleAdminLicenseDetail(request, env);
      if (request.method === "POST" && url.pathname === "/v1/admin/update") return await handleAdminUpdate(request, env);
      if (request.method === "POST" && url.pathname === "/v1/admin/revoke") return await handleAdminRevoke(request, env);
      if (request.method === "POST" && url.pathname === "/v1/admin/reset-devices") return await handleAdminResetDevices(request, env);
      if (request.method === "POST" && url.pathname === "/v1/admin/revoke-device") return await handleAdminRevokeDevice(request, env);
      return errorResponse("not_found", 404);
    } catch (error) {
      if (error instanceof RequestError) return errorResponse(error.code, error.status);
      console.error(error);
      return errorResponse("internal_error", 500);
    }
  }
};
var __test = {
  LICENSE_CONTRACT_VERSION,
  base64UrlEncode,
  base64UrlDecode,
  rawSignatureToDer,
  derSignatureToRaw,
  deviceKeyHash
};
var index_default = worker;
export {
  __test,
  index_default as default
};
//# sourceMappingURL=index.js.map
