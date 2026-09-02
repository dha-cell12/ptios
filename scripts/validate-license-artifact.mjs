import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFile, readdir, stat, writeFile } from "node:fs/promises";
import { basename, join, resolve } from "node:path";

function parseArgs(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i += 2) {
    const name = argv[i];
    const value = argv[i + 1];
    assert.ok(name?.startsWith("--") && value, `invalid argument near ${name || "end"}`);
    result[name.slice(2)] = value;
  }
  return result;
}

function decodeXML(value) {
  return value
    .replaceAll("&amp;", "&")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&apos;", "'");
}

function plistValue(xml, key) {
  const marker = `<key>${key}</key>`;
  const index = xml.indexOf(marker);
  assert.ok(index >= 0, `LicenseConfig.plist is missing ${key}`);
  const tail = xml.slice(index + marker.length).trimStart();
  const stringMatch = tail.match(/^<string>([\s\S]*?)<\/string>/);
  if (stringMatch) return decodeXML(stringMatch[1]);
  if (tail.startsWith("<true/>")) return true;
  if (tail.startsWith("<false/>")) return false;
  throw new Error(`unsupported plist value for ${key}`);
}

async function hashFile(path) {
  const data = await readFile(path);
  return createHash("sha256").update(data).digest("hex");
}

async function listFiles(path) {
  const output = [];
  for (const name of await readdir(path)) {
    const child = join(path, name);
    const info = await stat(child);
    if (info.isDirectory()) output.push(...await listFiles(child));
    else if (info.isFile()) output.push(child);
  }
  return output;
}

const args = parseArgs(process.argv.slice(2));
const app = resolve(args.app || "");
const tipa = resolve(args.tipa || "");
const mode = args.mode;
const output = resolve(args.output || `license-build-${mode}.json`);
assert.ok(mode === "observe" || mode === "enforced", "mode must be observe or enforced");

const expected = {
  LicenseEndpoint: args.endpoint,
  LicenseKeyID: args.keyId,
  LicensePublicKeyX: args.publicKeyX,
  LicensePublicKeyY: args.publicKeyY,
  LicenseEnforcementEnabled: mode === "enforced",
};
for (const [key, value] of Object.entries(expected)) {
  assert.notEqual(value, undefined, `missing expected value for ${key}`);
}

const configPath = join(app, "LicenseConfig.plist");
const appInfoPath = join(app, "Info.plist");
let configXML;
try {
  configXML = execFileSync("/usr/bin/plutil", ["-convert", "xml1", "-o", "-", configPath], { encoding: "utf8" });
} catch {
  configXML = await readFile(configPath, "utf8");
}
for (const [key, value] of Object.entries(expected)) {
  assert.equal(plistValue(configXML, key), value, `artifact ${key} does not match the CI input`);
}
let appInfoXML;
try {
  appInfoXML = execFileSync("/usr/bin/plutil", ["-convert", "xml1", "-o", "-", appInfoPath], { encoding: "utf8" });
} catch {
  appInfoXML = await readFile(appInfoPath, "utf8");
}
assert.equal(plistValue(appInfoXML, "UIApplicationShowsViewsWhileLocked"), true, "app lacks lock-screen UI permission");
assert.equal(plistValue(appInfoXML, "SecureKey"), true, "app lacks the secure-window bundle flag");
assert.match(expected.LicenseEndpoint, /^https:\/\//, "license endpoint must use HTTPS");
assert.doesNotMatch(expected.LicenseEndpoint, /REPLACE_|localhost|127\.0\.0\.1/i, "license endpoint is a placeholder or local address");
assert.doesNotMatch(expected.LicenseKeyID, /REPLACE_/i, "license key id is a placeholder");
assert.match(expected.LicensePublicKeyX, /^[A-Za-z0-9_-]{43}$/, "invalid P-256 public key X");
assert.match(expected.LicensePublicKeyY, /^[A-Za-z0-9_-]{43}$/, "invalid P-256 public key Y");

const executables = ["StreamControl", "streamd", "clipboardd", "vpnagent", "privhelper"];
const expectedMarker = mode === "enforced" ? "enforced_compile_time_v1" : "observe_compile_time_v1";
const unexpectedMarker = mode === "enforced" ? "observe_compile_time_v1" : "enforced_compile_time_v1";
const executableHashes = {};
for (const name of executables) {
  const path = join(app, name);
  const bytes = await readFile(path);
  const binary = bytes.toString("latin1");
  assert.ok(binary.includes(expectedMarker), `${name} lacks ${expectedMarker}`);
  assert.ok(!binary.includes(unexpectedMarker), `${name} unexpectedly contains ${unexpectedMarker}`);
  executableHashes[name] = createHash("sha256").update(bytes).digest("hex");
}

const appBinary = (await readFile(join(app, "StreamControl"))).toString("latin1");
const streamdBinary = (await readFile(join(app, "streamd"))).toString("latin1");
const clipboarddBinary = (await readFile(join(app, "clipboardd"))).toString("latin1");
const vpnagentBinary = (await readFile(join(app, "vpnagent"))).toString("latin1");
const uiServicePath = join(app, "TLinkUIService.app", "TLinkUIService");
const uiServiceInfoPath = join(app, "TLinkUIService.app", "Info.plist");
const uiServiceBytes = await readFile(uiServicePath);
const uiServiceBinary = uiServiceBytes.toString("latin1");
let uiServiceInfoXML;
try {
  uiServiceInfoXML = execFileSync("/usr/bin/plutil", ["-convert", "xml1", "-o", "-", uiServiceInfoPath], { encoding: "utf8" });
} catch {
  uiServiceInfoXML = await readFile(uiServiceInfoPath, "utf8");
}
executableHashes.TLinkUIService = createHash("sha256").update(uiServiceBytes).digest("hex");
const widgetPath = join(app, "PlugIns", "TLinkBootWidget.appex", "TLinkBootWidget");
const widgetBytes = await readFile(widgetPath);
const widgetBinary = widgetBytes.toString("latin1");
executableHashes.TLinkBootWidget = createHash("sha256").update(widgetBytes).digest("hex");
assert.ok(appBinary.includes("serviceVersion=23"), "StreamControl does not require service v23");
assert.ok(streamdBinary.includes("serviceVersion=23"), "streamd does not expose service v23");
assert.ok(appBinary.includes("StreamControl_app_6015"), "StreamControl lacks VPN P3 foreground broker evidence");
assert.ok(streamdBinary.includes("vpn_foreground_app_required"), "streamd lacks VPN P3 broker routing evidence");
assert.ok(appBinary.includes("vpn_on_demand_enabled"), "StreamControl lacks VPN P4 on-demand manager evidence");
assert.ok(appBinary.includes("Auto-Reconnect (On Demand)"), "StreamControl lacks VPN P4 local UI evidence");
assert.ok(streamdBinary.includes("vpnPhase=5"), "streamd lacks VPN P5 capability evidence");
assert.ok(streamdBinary.includes("vpnState=background_control"), "streamd lacks promoted VPN P5 state evidence");
assert.ok(streamdBinary.includes("vpnBackgroundAgent=candidate_mobile_process_v3_private_compat"), "streamd lacks VPN private compatibility candidate evidence");
assert.ok(streamdBinary.includes("vpnagent_6016_then_StreamControl_6015"), "streamd lacks VPN P5 routing evidence");
assert.ok(streamdBinary.includes("direct_streamd_to_uiservice_no_worker_v1"), "streamd lacks direct Vision OCR dispatch evidence");
assert.ok(streamdBinary.includes("inline_rgba8888_bounded_32mib_v2"), "streamd lacks bounded raw Vision OCR transport evidence");
assert.ok(streamdBinary.includes("protocol3_inline_png_compat_only"), "streamd lacks Vision OCR compatibility fallback evidence");
assert.ok(vpnagentBinary.includes("vpnagent_ready version=3 phase=5"), "vpnagent lacks P5 readiness evidence");
assert.ok(vpnagentBinary.includes("vpnagent refuses non-mobile identity"), "vpnagent lacks fail-closed mobile identity evidence");
assert.ok(vpnagentBinary.includes("background_vpnagent"), "vpnagent lacks P5 diagnostics evidence");
assert.ok(widgetBinary.includes("SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions"), "boot widget lacks the SpringBoardServices wake path");
assert.ok(widgetBinary.includes("SBSLaunchApplicationWithIdentifier"), "boot widget lacks the simple SpringBoardServices fallback");
assert.ok(widgetBinary.includes("LSApplicationWorkspace"), "boot widget lacks the LaunchServices fallback");
assert.ok(widgetBinary.includes("/var/mobile/Library/TLinkauto/runtime/widget_boot_wake.plist"), "boot widget lacks wake diagnostics");
assert.ok(widgetBinary.includes("com.tlinkauto.streamcontrol"), "boot widget lacks the StreamControl host identifier");
assert.ok(clipboarddBinary.includes("clipboardd_ready;;version=16"), "clipboardd does not expose service v16");
assert.ok(clipboarddBinary.includes("registered_keyboard_page_12_usage_233"), "clipboardd lacks the direct IOHID Volume Up listener");
assert.ok(clipboarddBinary.includes("Volume Up was pressed twice."), "clipboardd lacks the volume action menu");
assert.ok(clipboarddBinary.includes("volume_menu_backend=cfusernotification_primary_secure_uiwindow_fallback"), "clipboardd lacks the system-alert volume menu backend");
assert.ok(clipboarddBinary.includes("/var/mobile/Library/TLinkauto/runtime/volume_trigger.plist"), "clipboardd lacks volume-trigger diagnostics");
assert.ok(clipboarddBinary.includes("background_visual_uiservice_queued"), "clipboardd lacks the background toast UI-service route");
assert.ok(clipboarddBinary.includes("TLinkUIService.app/TLinkUIService"), "clipboardd lacks UI-service self-recovery");
assert.ok(clipboarddBinary.includes("uiservice plugin spawn"), "clipboardd lacks hosted-plugin UI-service launch");
assert.ok(uiServiceBinary.includes("uiservice_ready;;version=24"), "TLinkUIService lacks v24 readiness evidence");
assert.ok(uiServiceBinary.includes("uiservice_ocr_ready"), "TLinkUIService lacks the background Vision OCR endpoint");
assert.ok(uiServiceBinary.includes("background_uiservice_6018"), "TLinkUIService lacks background Vision host evidence");
assert.ok(uiServiceBinary.includes("protocol=4"), "TLinkUIService lacks Vision OCR protocol v4");
assert.ok(uiServiceBinary.includes("transport=inline_rgba8888"), "TLinkUIService lacks raw inline Vision OCR transport");
assert.ok(uiServiceBinary.includes("fallback_protocol=3"), "TLinkUIService lacks Vision OCR v3 fallback");
assert.ok(uiServiceBinary.includes("vision_ocr_inline_max_bytes=33554432"), "TLinkUIService lacks the inline OCR size bound");
assert.ok(uiServiceBinary.includes("xxtouch_sbs_accessibility_context_registration"), "TLinkUIService lacks SBS accessibility context hosting");
assert.ok(uiServiceBinary.includes("window_scene_attachment_enabled=0"), "TLinkUIService does not disable the black-screen UIWindowScene path");
assert.ok(uiServiceBinary.includes("SBSAccessibilityWindowHostingController"), "TLinkUIService lacks the accessibility window hosting controller");
assert.ok(uiServiceBinary.includes("registerWindowWithContextID:atLevel:"), "TLinkUIService lacks CA context registration");
assert.ok(uiServiceBinary.includes("unregisterWindowWithContextID:"), "TLinkUIService lacks CA context cleanup");
assert.ok(uiServiceBinary.includes("system_window_override_installed"), "TLinkUIService lacks system-window diagnostics");
assert.ok(uiServiceBinary.includes("window_level_hook_installed"), "TLinkUIService lacks window-level hook diagnostics");
assert.ok(uiServiceBinary.includes("toast_rejected_no_compositor_hosting"), "TLinkUIService does not fail closed when compositor hosting is unavailable");
assert.ok(uiServiceBinary.includes("plugin_hosted_ready"), "TLinkUIService lacks hosted-plugin lifecycle evidence");
assert.ok(uiServiceBinary.includes("__completeAndRunAsPlugin"), "TLinkUIService lacks BackBoard plugin completion evidence");
assert.ok(!uiServiceBinary.includes("createSceneWithDefinition:initialParameters:"), "TLinkUIService still contains the black-screen synthetic scene path");
assert.ok(!uiServiceBinary.includes("UIRootWindowScenePresentationBinder"), "TLinkUIService still contains a synthetic scene binder");
assert.ok(uiServiceBinary.includes("window_ready_accessibility_hosted"), "TLinkUIService lacks hosted-window readiness evidence");
assert.ok(uiServiceBinary.includes("/var/mobile/Library/TLinkauto/runtime/uiservice_toast.plist"), "TLinkUIService lacks diagnostics");
assert.equal(plistValue(uiServiceInfoXML, "CFBundleIdentifier"), "com.tlinkauto.streamcontrol.uiservice", "TLinkUIService has the wrong bundle identifier");
assert.equal(plistValue(uiServiceInfoXML, "UIApplicationShowsViewsWhileLocked"), true, "TLinkUIService lacks lock-screen UI permission");
assert.equal(plistValue(uiServiceInfoXML, "UIApplicationExitsOnSuspend"), false, "TLinkUIService suspend policy is missing");
assert.equal(plistValue(uiServiceInfoXML, "LSUIElement"), true, "TLinkUIService must remain a non-full-screen UI agent");
assert.ok(!uiServiceInfoXML.includes("<key>UIRequiresFullScreen</key>"), "TLinkUIService must not seize a full-screen presentation");
assert.equal(plistValue(uiServiceInfoXML, "SecureKey"), true, "TLinkUIService lacks the secure-window bundle flag");
assert.equal(plistValue(uiServiceInfoXML, "UIApplicationSystemWindowsSecureKey"), true, "TLinkUIService lacks the system secure-window bundle flag");
assert.equal(plistValue(uiServiceInfoXML, "NSPrincipalClass"), "TLinkUIServiceApplication", "TLinkUIService lacks the hosted UIApplication principal class");
assert.equal(plistValue(uiServiceInfoXML, "CFBundleVersion"), "24", "TLinkUIService bundle version is stale");
assert.ok(appInfoXML.includes("TLinkUIService.app/TLinkUIService"), "TSRootBinaries does not include TLinkUIService");

const appEntitlements = execFileSync("ldid", ["-e", join(app, "StreamControl")], { encoding: "utf8" });
const streamdEntitlements = execFileSync("ldid", ["-e", join(app, "streamd")], { encoding: "utf8" });
const clipboarddEntitlements = execFileSync("ldid", ["-e", join(app, "clipboardd")], { encoding: "utf8" });
const uiServiceEntitlements = execFileSync("ldid", ["-e", uiServicePath], { encoding: "utf8" });
const vpnagentEntitlements = execFileSync("ldid", ["-e", join(app, "vpnagent")], { encoding: "utf8" });
const widgetEntitlements = execFileSync("ldid", ["-e", widgetPath], { encoding: "utf8" });
assert.ok(
  appEntitlements.includes("com.apple.developer.networking.vpn.api") &&
    appEntitlements.includes("allow-vpn"),
  "StreamControl is missing the signed allow-vpn entitlement",
);
assert.ok(
  vpnagentEntitlements.includes("com.apple.developer.networking.vpn.api") &&
    vpnagentEntitlements.includes("allow-vpn"),
  "vpnagent is missing the signed allow-vpn entitlement",
);
assert.ok(
  vpnagentEntitlements.includes("com.apple.SystemConfiguration.SCPreferences-write-access") &&
    vpnagentEntitlements.includes("preferences.plist"),
  "vpnagent is missing the private VPN preference write entitlement",
);
assert.ok(
  vpnagentEntitlements.includes("keychain-access-groups") &&
    vpnagentEntitlements.includes("StreamCtl.com.tlinkauto.streamcontrol"),
  "vpnagent is missing the TrollStore VPN Keychain group",
);
assert.ok(
  !vpnagentEntitlements.includes("com.apple.developer.networking.networkextension") &&
    !vpnagentEntitlements.includes("packet-tunnel-provider"),
  "vpnagent must not receive packet-tunnel-provider entitlement",
);
assert.ok(
  appEntitlements.includes("keychain-access-groups") &&
    appEntitlements.includes("StreamCtl.com.tlinkauto.streamcontrol"),
  "StreamControl is missing the TrollStore VPN Keychain group",
);
assert.ok(
  appEntitlements.includes("com.apple.SystemConfiguration.SCPreferences-write-access") &&
    appEntitlements.includes("preferences.plist"),
  "StreamControl is missing the private VPN preference write entitlement",
);
for (const [name, entitlements] of [
  ["StreamControl", appEntitlements],
  ["streamd", streamdEntitlements],
]) {
  assert.ok(
    entitlements.includes("com.apple.private.tcc.allow") &&
      entitlements.includes("kTCCServicePhotos") &&
      entitlements.includes("kTCCServicePhotosAdd"),
    `${name} is missing the signed zero-touch Photos TCC services`,
  );
}
assert.ok(
  !streamdEntitlements.includes("com.apple.developer.networking.vpn.api") &&
    !streamdEntitlements.includes("com.apple.developer.networking.networkextension"),
  "streamd must not inherit VPN or packet-tunnel entitlements",
);
assert.ok(
  widgetEntitlements.includes("com.apple.backboardd.launchapplications") &&
    widgetEntitlements.includes("platform-application"),
  "boot widget is missing its TrollStore launch entitlements",
);
assert.ok(
  clipboarddEntitlements.includes("com.apple.private.hid.client.event-monitor") &&
    clipboarddEntitlements.includes("IOHIDEventSystemUserClient") &&
    clipboarddEntitlements.includes("com.apple.springboard.launchapplications"),
  "clipboardd is missing direct IOHID or UI-service launch entitlements",
);
assert.ok(
  uiServiceEntitlements.includes("platform-application") &&
    uiServiceEntitlements.includes("com.apple.private.extension-host") &&
    uiServiceEntitlements.includes("com.apple.developer.networking.HotspotHelper") &&
    uiServiceEntitlements.includes("com.apple.developer.networking.multicast") &&
    uiServiceEntitlements.includes("com.apple.developer.networking.vpn.api") &&
    uiServiceEntitlements.includes("allow-vpn") &&
    uiServiceEntitlements.includes("com.apple.springboard.launchapplications") &&
    uiServiceEntitlements.includes("com.apple.runningboard.assertions.frontboard") &&
    uiServiceEntitlements.includes("com.apple.backboardd.hostCanRequireTouchesFromHostedContent") &&
    uiServiceEntitlements.includes("com.apple.QuartzCore.displayable-context") &&
    uiServiceEntitlements.includes("com.apple.QuartzCore.secure-mode") &&
    uiServiceEntitlements.includes("com.apple.private.IOSurface.protected-access") &&
    uiServiceEntitlements.includes("com.apple.UIKit.statusbarserver") &&
    uiServiceEntitlements.includes("com.apple.springboard.SBRendererService") &&
    uiServiceEntitlements.includes("<key>application-identifier</key>") &&
    uiServiceEntitlements.includes("com.tlinkauto.streamcontrol.uiservice") &&
    !uiServiceEntitlements.includes("com.apple.QuartzCore.system-layers") &&
    !uiServiceEntitlements.includes("com.apple.developer.team-identifier"),
  "TLinkUIService is missing its TrollStore background UI entitlement set",
);

const forbidden = [
  "LICENSE_SIGNING_PRIVATE_JWK",
  "TLINK_LICENSE_ADMIN_TOKEN",
  "BEGIN EC PRIVATE KEY",
  "BEGIN PRIVATE KEY",
  '"key_ops":["sign"]',
];
for (const path of await listFiles(app)) {
  const content = (await readFile(path)).toString("latin1");
  for (const token of forbidden) {
    assert.ok(!content.includes(token), `${basename(path)} contains forbidden secret marker ${token}`);
  }
}

const manifest = {
  schema_version: 1,
  product: "tlinkauto-trollstore",
  license_contract_version: 1,
  license_mode: mode,
  compile_marker: expectedMarker,
  service_version: 23,
  vpn_phase: 5,
  vpn_state: "background_control",
  vpn_agent_version: 3,
  vpn_profile_bootstrap: "private_no_consent_with_ne_fallback",
  config: {
    endpoint: expected.LicenseEndpoint,
    key_id: expected.LicenseKeyID,
    public_key_x: expected.LicensePublicKeyX,
    public_key_y: expected.LicensePublicKeyY,
    enforcement_enabled: expected.LicenseEnforcementEnabled,
  },
  sha256: {
    tipa: await hashFile(tipa),
    license_config: await hashFile(configPath),
    executables: executableHashes,
  },
  secret_scan: "passed",
};

await writeFile(output, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
console.log(`license artifact OK: ${mode}, service v23, manifest ${output}`);
