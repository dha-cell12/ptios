export function renderAdminDashboard(nonce) {
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
    .auth-guide-actions { margin-top: 14px; }
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
    #guide-dialog { width: min(860px, calc(100% - 24px)); }
    .guide-content { line-height: 1.55; }
    .guide-content h3 { margin: 0 0 8px; font-size: 16px; }
    .guide-content p { margin: 0 0 10px; }
    .guide-content ul, .guide-content ol { margin: 8px 0 0; padding-left: 22px; }
    .guide-content li + li { margin-top: 6px; }
    .guide-section { padding-bottom: 16px; border-bottom: 1px solid #e7ebef; }
    .guide-section:last-child { padding-bottom: 0; border-bottom: 0; }
    .guide-callout {
      padding: 11px 12px; border: 1px solid #c7dafa; border-radius: 6px;
      background: #eef5ff; color: #17457f;
    }
    .guide-callout.warning { border-color: #efd49b; background: #fff8e8; color: #744b00; }
    .guide-table { width: 100%; border: 1px solid #e1e5ea; border-radius: 6px; border-collapse: separate; border-spacing: 0; overflow: hidden; }
    .guide-table th, .guide-table td { padding: 9px 10px; font-size: 13px; text-transform: none; }
    code { padding: 2px 5px; border-radius: 4px; background: #edf2f7; font-family: ui-monospace, SFMono-Regular, Consolas, monospace; }
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
        <button id="guide-button" class="button quiet" type="button">Hướng dẫn</button>
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
      <div class="actions auth-guide-actions">
        <button id="auth-guide-button" class="button quiet" type="button">Xem hướng dẫn quản trị</button>
      </div>
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

  <dialog id="guide-dialog" aria-labelledby="guide-title">
    <div class="dialog-head">
      <div>
        <h2 id="guide-title">Hướng dẫn quản trị license</h2>
        <div class="muted small">Áp dụng cho dashboard Worker tại <code>/admin</code></div>
      </div>
      <button class="button quiet" data-close="guide-dialog" type="button" aria-label="Đóng hướng dẫn">Đóng</button>
    </div>
    <div class="dialog-body guide-content">
      <section class="guide-section">
        <h3>1. Đăng nhập an toàn</h3>
        <ol>
          <li>Mở dashboard bằng HTTPS và nhập đúng secret <code>ADMIN_TOKEN</code> của Worker.</li>
          <li>Token chỉ nằm trong bộ nhớ của tab hiện tại; dashboard không ghi vào cookie hay local storage.</li>
          <li>Nhấn <strong>Lock</strong> trước khi rời máy dùng chung. Không gửi token qua chat, log hoặc ảnh chụp.</li>
        </ol>
      </section>

      <section class="guide-section">
        <h3>2. Tạo license mới</h3>
        <ol>
          <li>Nhấn <strong>New License</strong>, dùng key được tạo tự động hoặc nhập key riêng.</li>
          <li>Đặt <strong>Maximum devices</strong> là số thiết bị được active đồng thời.</li>
          <li>Chọn ngày hết hạn; để trống nếu license vĩnh viễn.</li>
          <li>Chọn ít nhất một feature rồi nhấn <strong>Create License</strong>.</li>
          <li>Sao chép key ngay khi kết quả xuất hiện. Worker chỉ lưu SHA-256 hash nên không thể xem lại clear key.</li>
        </ol>
      </section>

      <section class="guide-section">
        <h3>3. Ý nghĩa feature</h3>
        <table class="guide-table">
          <thead><tr><th>Feature</th><th>Cho phép</th></tr></thead>
          <tbody>
            <tr><td><code>automation</code></td><td>Touch, app/process, clipboard, OCR, VPN và các tác vụ tự động hóa thông thường.</td></tr>
            <tr><td><code>stream</code></td><td>Nhận luồng H264 và feedback Adaptive Streaming.</td></tr>
            <tr><td><code>script</code></td><td>Chạy/dừng script, scheduler, log và runtime script.</td></tr>
            <tr><td><code>admin</code></td><td>Clear app data, kill app, respring và tác vụ quản trị nhạy cảm.</td></tr>
            <tr><td><code>shell</code></td><td>Thực thi shell; thiết bị vẫn phải bật local setting cho shell.</td></tr>
          </tbody>
        </table>
      </section>

      <section class="guide-section">
        <h3>4. Quản lý một license</h3>
        <ul>
          <li><strong>Save Changes:</strong> cập nhật status, số thiết bị, ngày hết hạn và feature.</li>
          <li><strong>Revoke thiết bị:</strong> thu hồi một binding và giải phóng một slot; thiết bị đó có thể active lại nếu còn slot và còn key.</li>
          <li><strong>Reset Device Slots:</strong> revoke toàn bộ binding đang active và xóa challenge dở dang. Dùng sau restore, đổi máy hoặc mất private key.</li>
          <li><strong>Revoke License:</strong> chặn activation/refresh của toàn bộ license. Chỉ chọn lại status Active khi thực sự muốn cấp quyền trở lại.</li>
        </ul>
        <p class="guide-callout warning"><strong>Lưu ý:</strong> thay đổi server không sửa lease đã ký đang nằm trên thiết bị. Muốn kiểm tra ngay, mở Settings → License → Refresh Lease hoặc chờ lifecycle refresh; revoke sẽ bị phát hiện ở lần refresh kế tiếp.</p>
      </section>

      <section class="guide-section">
        <h3>5. Đọc trạng thái</h3>
        <ul>
          <li><strong>Active:</strong> license đang bật và chưa đến ngày hết hạn.</li>
          <li><strong>Expired:</strong> status vẫn active nhưng đã qua License expiration.</li>
          <li><strong>Revoked:</strong> license đã bị thu hồi thủ công.</li>
          <li><strong>Devices A / B:</strong> A là binding active hiện tại, B là giới hạn thiết bị.</li>
          <li><strong>License expiration</strong> là hạn quyền cố định; khác với hạn lease ngắn được gia hạn tự động trên thiết bị.</li>
        </ul>
      </section>

      <section class="guide-section">
        <h3>6. Xử lý lỗi nhanh</h3>
        <ul>
          <li><code>Unauthorized</code>: kiểm tra hoặc rotate <code>ADMIN_TOKEN</code>, sau đó deploy secret lại.</li>
          <li><code>license_exists</code>: key đã tồn tại; tạo một key mới.</li>
          <li><code>device_limit_reached</code>: revoke thiết bị cũ hoặc Reset Device Slots.</li>
          <li><code>device_revoked</code>: active lại bằng key; nếu thiết bị đã đổi private key, reset slot trước.</li>
          <li><code>license_revoked_or_expired</code>: kiểm tra status và License expiration rồi Refresh Lease.</li>
          <li><code>device_mismatch</code> hoặc thiếu private key: không copy lease giữa máy; reset slot và active lại trên đúng thiết bị.</li>
        </ul>
        <p class="guide-callout">Sau thao tác quản trị, kiểm tra task 75: trạng thái mong đợi là <code>valid</code> hoặc <code>offline_grace</code>, với <code>effective_access=true</code> và <code>device_key_proof=true</code>.</p>
      </section>
    </div>
    <div class="dialog-foot">
      <button class="button primary" data-close="guide-dialog" type="button">Đã hiểu</button>
    </div>
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

      function openGuide() {
        byId("guide-dialog").showModal();
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
      byId("guide-button").addEventListener("click", openGuide);
      byId("auth-guide-button").addEventListener("click", openGuide);
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
  </script>
</body>
</html>`;
}
