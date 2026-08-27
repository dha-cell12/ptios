import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");

const aggregate = read("stream-app/Makefile");
const makefile = read("stream-app/uiservice/Makefile");
const info = read("stream-app/uiservice/Info.plist");
const entitlements = read("stream-app/uiservice/entitlements.plist");
const source = read("stream-app/uiservice/main.mm");
const appInfo = read("stream-app/app/Info.plist");
const helper = read("stream-app/privhelper/main.mm");
const clipboardd = read("stream-app/clipboardd/main.mm");
const clipboarddEntitlements = read("stream-app/clipboardd/entitlements.plist");
const streamd = read("stream-app/streamd/POCSocketServer.mm");
const settings = read("stream-app/app/SettingsViewController.mm");
const appDelegate = read("stream-app/app/AppDelegate.mm");
const workflow = read(".github/workflows/stream-app.yml");
const runtimeStatus = read("docs/trollstore-runtime-status.md");

assert.match(makefile, /TOOL_NAME = TLinkUIService/);
assert.match(aggregate, /^uiservice:/m);
assert.match(aggregate, /embed: streamd clipboardd uiservice/);
assert.match(aggregate, /TLinkUIService\.app\/TLinkUIService/);
assert.match(aggregate, /ldid -Suiservice\/entitlements\.plist/);
assert.match(appInfo, /TLinkUIService\.app\/TLinkUIService/);

assert.match(info, /com\.tlinkauto\.streamcontrol\.uiservice/);
assert.match(info, /UIApplicationShowsViewsWhileLocked/);
assert.match(info, /UIApplicationExitsOnSuspend/);
assert.match(info, /<key>SecureKey<\/key>/);
assert.match(info, /<string>hidden<\/string>/);
assert.match(entitlements, /platform-application/);
assert.match(entitlements, /com\.apple\.private\.extension-host/);
assert.match(entitlements, /com\.apple\.developer\.networking\.HotspotHelper/);
assert.match(entitlements, /com\.apple\.developer\.networking\.multicast/);
assert.match(entitlements, /com\.apple\.developer\.networking\.vpn\.api/);
assert.match(entitlements, /com\.apple\.springboard\.launchapplications/);

assert.match(source, /htons\(6017\)/);
assert.match(source, /windowLevel = \(UIWindowLevel\)20000099\.9/);
assert.match(source, /- \(UIView \*\)hitTest:[\s\S]*return nil;/);
assert.match(source, /userInteractionEnabled = NO/);
assert.match(source, /_shouldCreateContextAsSecure/);
assert.match(source, /allow_screenshot/);
assert.match(source, /setgid\(501\)/);
assert.match(source, /setuid\(501\)/);
assert.match(source, /uiservice_ready;;version=4/);
assert.match(source, /request_count/);
assert.match(source, /UIApplicationMain\(argc, argv/);
assert.match(source, /didFinishLaunchingWithOptions/);
assert.match(source, /window_context_id/);
assert.match(source, /restore_frontmost/);
assert.match(source, /uiservice_restore_bundle/);
assert.doesNotMatch(source, /__completeAndRunAsPlugin/);
assert.match(source, /uiservice_toast\.plist/);

assert.match(helper, /TLinkEnsureUIService/);
assert.match(helper, /TLinkUIServiceProbeIsCurrent/);
assert.match(helper, /TLinkHelperOpenBundleWithSBS\(@"com\.tlinkauto\.streamcontrol\.uiservice"/);
assert.match(helper, /posix_spawnattr_set_persona_uid_np\(&attr, 501\)/);
assert.match(helper, /TLinkHelperSendLoopbackLine\(@"ping\\n", 6017/);
assert.match(helper, /uiservice deferred_on_replace/);
assert.match(clipboardd, /TLinkSendUIServiceToast\(payload\)/);
assert.match(clipboardd, /TLinkRespawnUIService/);
assert.match(clipboardd, /SBSLaunchApplicationWithIdentifier/);
assert.match(clipboardd, /uiservice_restore_bundle/);
assert.match(clipboarddEntitlements, /com\.apple\.springboard\.launchapplications/);
assert.match(clipboardd, /background_visual_uiservice_queued/);
assert.match(clipboardd, /CFUserNotification fallback/);
assert.match(streamd, /backgroundToastUIService/);
assert.match(streamd, /@"backgroundPositionedToastOverlay": @\(YES\)/);
assert.match(streamd, /foreground_or_background_uiservice_positioned_with_cf_fallback/);
assert.match(streamd, /@"allow_screenshot": @\(allowScreenshot\)/);
assert.match(streamd, /BOOL forceUIService = \[kind isEqualToString:@"toast"\]/);
assert.match(streamd, /@"delivery": @"uiservice"/);
assert.match(appDelegate, /\[event\[@"delivery"\] isEqualToString:@"uiservice"\]/);
assert.match(settings, /UI service v4/);

assert.match(settings, /Toast UI Service Status/);
assert.match(settings, /Show Background Toast Test/);
assert.ok(settings.includes('@"2411\\n"'));
assert.ok(settings.includes('@"2412\\n"'));
assert.match(settings, /kTLinkUIServiceDiagnosticsPath/);
assert.match(workflow, /node scripts\/check-trollstore-toast-uiservice\.mjs/);
assert.match(workflow, /Payload\/StreamControl\.app\/TLinkUIService\.app\/TLinkUIService/);
assert.match(runtimeStatus, /TLinkUIService/);

console.log("TrollStore background toast UI service contract checks passed");
