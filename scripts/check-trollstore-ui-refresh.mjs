import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const contains = (source, marker, label) =>
  assert.ok(source.includes(marker), `${label} lacks ${marker}`);

const requiredFiles = [
  "stream-app/app/DashboardViewController.h",
  "stream-app/app/DashboardViewController.mm",
  "stream-app/app/ServiceLogViewController.h",
  "stream-app/app/ServiceLogViewController.mm",
  "stream-app/app/TLinkLogStore.h",
  "stream-app/app/TLinkLogStore.mm",
  "stream-app/app/TLinkTheme.h",
  "stream-app/app/TLinkTheme.mm",
];
for (const path of requiredFiles) {
  assert.ok(existsSync(path), `missing TrollStore UI component ${path}`);
}
assert.equal(existsSync("stream-app/app/ViewController.mm"), false,
  "legacy ViewController.mm must remain removed");
assert.equal(existsSync("stream-app/app/ViewController.h"), false,
  "legacy ViewController.h must remain removed");

const appDelegate = read("stream-app/app/AppDelegate.mm");
contains(appDelegate, "@[dashboardNav, scriptsNav, settingsNav]", "AppDelegate.mm");
contains(appDelegate, "applyCurrentAppearanceStyleToWindow", "AppDelegate.mm");

const makefile = read("stream-app/app/Makefile");
for (const file of [
  "TLinkTheme.mm",
  "TLinkLogStore.mm",
  "DashboardViewController.mm",
  "ServiceLogViewController.mm",
]) {
  contains(makefile, file, "stream-app/app/Makefile");
}
assert.doesNotMatch(makefile, /(^|\s)ViewController\.mm(\s|$)/m,
  "legacy ViewController.mm must not be compiled");

const dashboard = read("stream-app/app/DashboardViewController.mm");
for (const marker of [
  "Ensure service",
  "Restart streamd",
  "Self-test tap (center)",
  "Capture probe",
  "TLinkLogStoreDidAppendNotification",
]) {
  contains(dashboard, marker, "DashboardViewController.mm");
}

const theme = read("stream-app/app/TLinkTheme.mm");
for (const marker of [
  "TLinkAppearanceStyleSystem",
  "TLinkAppearanceStyleLight",
  "TLinkAppearanceStyleDark",
  "UIButtonConfiguration",
]) {
  contains(theme, marker, "TLinkTheme.mm");
}

const scripts = read("stream-app/app/ScriptsViewController.mm");
for (const marker of [
  "UISearchResultsUpdating",
  "updateSearchResultsForSearchController",
  "No matching scripts",
  "headerButtonWithSystemImage",
  "10 Failure Evidence.tl",
]) {
  contains(scripts, marker, "ScriptsViewController.mm");
}

const settings = read("stream-app/app/SettingsViewController.mm");
for (const marker of [
  "presentAppearancePicker",
  "Managed VPN",
  "SCLicenseViewController",
  "Danger Zone",
]) {
  contains(settings, marker, "SettingsViewController.mm");
}

const editor = read("stream-app/app/ScriptEditorViewController.mm");
for (const marker of [
  "applySyntaxHighlighting",
  "markedTextRange",
  "length <= 60000",
  "stringCommentRegex",
]) {
  contains(editor, marker, "ScriptEditorViewController.mm");
}

console.log("TrollStore UI refresh OK: dashboard, theme, search, settings, log and editor contracts");
