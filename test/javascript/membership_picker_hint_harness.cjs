// Executed proof for the QA-04 memberships-page inline init
// (app/views/dwar/admin/memberships/index.html.erb).
//
// No dependencies: node stdlib only (fs, path, vm). Run with:
//   node test/javascript/membership_picker_hint_harness.cjs
//
// The harness loads the ACTUAL inline <script> from the view (not a copy),
// then runs it under stubbed document/console/DwarUserPicker globals across
// six scenarios. Exit 0 + "HINT-HARNESS-OK" means:
//   - the hint markup is hidden by default, uses role="status", and keeps
//     dev detail (README) out of the visible text;
//   - the inline script unhides the hint (hidden false) + console.warns on
//     every silent path (missing library, missing markup, missing
//     input/hidden/url, init returning no handle, init throwing);
//   - the happy path leaves the hint hidden with no warning;
//   - the inline script never throws outward in any scenario.
// Any failure prints "HINT-HARNESS-FAIL" and exits non-zero. Executed in
// CI-by-proxy through test/membership_picker_wiring_test.rb (skipped when
// node is unavailable).
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const VIEW = path.join(
  __dirname, "..", "..", "app", "views", "dwar", "admin", "memberships", "index.html.erb"
);

function assert(cond, message) {
  if (!cond) {
    throw new Error(message);
  }
}

function loadView() {
  return fs.readFileSync(VIEW, "utf8");
}

// The inline init is the only <script> without a src attribute.
function extractInlineScript(view) {
  const matches = [...view.matchAll(/<script(?![^>]*\bsrc\b)[^>]*>([\s\S]*?)<\/script>/g)];
  assert(matches.length >= 1, "expected an inline <script> in memberships index view");
  return matches.map((m) => m[1]).join("\n");
}

function checkStaticContract(view, script) {
  const hintMatch = view.match(/<p[^>]*data-dwar-picker-missing[^>]*>([\s\S]*?)<\/p>/);
  assert(hintMatch, "expected a <p data-dwar-picker-missing> hint in the view");
  const hintTag = hintMatch[0];
  const hintText = hintMatch[1];
  assert(/\bhidden\b/.test(hintTag), "hint must carry the hidden attribute by default");
  assert(/role="status"/.test(hintTag), "hint must carry role=\"status\" for assistive tech");
  assert(!/README/i.test(hintText), "visible hint text must stay generic (README detail lives in console.warn only)");
  assert(/Autocomplete unavailable/.test(hintText), "visible hint text must tell the admin the form still submits");

  assert(script.includes("hint.hidden = false"), "inline script must unhide the hint");
  assert(script.includes("console.warn"), "inline script must pair the hint with a console.warn");
  assert(script.includes("DwarUserPicker is not loaded"), "inline script must handle a missing library");
  assert(
    script.includes("picker markup or endpoint missing"),
    "inline script must validate input/hidden/url instead of passing falsy values to init"
  );
  assert(
    script.includes("picker init returned no handle"),
    "inline script must surface an init that returns no handle (undefined) instead of staying silent"
  );
}

function makeSandbox({hint, root, picker}) {
  const warnings = [];
  const sandbox = {
    document: {
      querySelector(selector) {
        if (selector === "[data-dwar-picker-missing]") {
          return hint;
        }
        if (selector === "[data-dwar-user-picker]") {
          return root;
        }
        return null;
      }
    },
    console: {
      warn(message) {
        warnings.push(String(message));
      }
    }
  };
  if (picker !== undefined) {
    sandbox.DwarUserPicker = picker;
  }
  return {sandbox, warnings};
}

function runInline(script, sandbox) {
  // Any outward throw is a harness failure: the inline init must never throw.
  vm.runInNewContext(script, sandbox, {filename: "memberships-inline-init.js"});
}

function makeInput() {
  return {kind: "input"};
}

function makeHiddenField() {
  return {kind: "hidden"};
}

function makeRoot({url, input, hiddenField}) {
  return {
    dataset: url === undefined ? {} : {url},
    querySelector(selector) {
      if (selector === "[data-dwar-user-picker-input]") {
        return input === undefined ? makeInput() : input;
      }
      if (selector === "[data-dwar-user-picker-hidden]") {
        return hiddenField === undefined ? makeHiddenField() : hiddenField;
      }
      return null;
    }
  };
}

function checkWarnedForMissingScript(warnings) {
  assert(warnings.length === 1, `expected 1 console.warn, got ${warnings.length}`);
  assert(warnings[0].includes("README"), "console.warn must point at the README wiring docs");
}

function scenarioMissingLibrary(script) {
  const hint = {hidden: true};
  const {sandbox, warnings} = makeSandbox({
    hint,
    root: makeRoot({url: "/dwar/admin/users.json"})
  });
  runInline(script, sandbox);
  assert(hint.hidden === false, "missing library must unhide the hint (hidden false)");
  assert(warnings.length === 1, "missing library must log exactly one console.warn");
  assert(warnings[0].includes("DwarUserPicker is not loaded"), "warn must name the missing library");
  checkWarnedForMissingScript(warnings);
}

function scenarioMissingMarkup(script) {
  const hint = {hidden: true};
  const {sandbox, warnings} = makeSandbox({hint, root: null});
  runInline(script, {...sandbox, DwarUserPicker: {init() { return {destroy() {}}; }}});
  assert(hint.hidden === false, "missing picker markup must unhide the hint");
  assert(warnings.length === 1, "missing picker markup must console.warn");
  assert(warnings[0].includes("picker markup not found"), "warn must name the missing markup");
}

function scenarioMissingEndpoint(script) {
  const hint = {hidden: true};
  let initCalled = false;
  const {sandbox, warnings} = makeSandbox({
    hint,
    root: makeRoot({url: undefined}),
    picker: {init() {
      initCalled = true;
      return {destroy() {}};
    }}
  });
  runInline(script, sandbox);
  assert(hint.hidden === false, "missing endpoint url must unhide the hint");
  assert(warnings.length === 1, "missing endpoint url must console.warn");
  assert(warnings[0].includes("picker markup or endpoint missing"), "warn must name the missing endpoint");
  assert(initCalled === false, "init must not run when input/hidden/url is missing");
}

function scenarioMissingInput(script) {
  const hint = {hidden: true};
  let initCalled = false;
  const {sandbox, warnings} = makeSandbox({
    hint,
    root: makeRoot({url: "/dwar/admin/users.json", input: null, hiddenField: makeHiddenField()}),
    picker: {init() {
      initCalled = true;
      return {destroy() {}};
    }}
  });
  runInline(script, sandbox);
  assert(hint.hidden === false, "missing input must unhide the hint");
  assert(warnings.length === 1, "missing input must console.warn");
  assert(initCalled === false, "init must not run when the input is missing");
}

function scenarioInitReturnsNoHandle(script) {
  const hint = {hidden: true};
  const {sandbox, warnings} = makeSandbox({
    hint,
    root: makeRoot({url: "/dwar/admin/users.json"}),
    picker: {init() { return undefined; }}
  });
  runInline(script, sandbox);
  assert(hint.hidden === false, "init returning undefined must unhide the hint (never stay silent)");
  assert(warnings.length === 1, "init returning undefined must console.warn");
  assert(warnings[0].includes("no handle"), "warn must name the missing handle");
}

function scenarioInitThrows(script) {
  const hint = {hidden: true};
  const {sandbox, warnings} = makeSandbox({
    hint,
    root: makeRoot({url: "/dwar/admin/users.json"}),
    picker: {init() { throw new Error("boom"); }}
  });
  runInline(script, sandbox);
  assert(hint.hidden === false, "throwing init must unhide the hint");
  assert(warnings.length === 1, "throwing init must console.warn");
  assert(warnings[0].includes("picker init failed"), "warn must name the failed init");
}

function scenarioHappyPath(script) {
  const hint = {hidden: true};
  let initArgs = null;
  const {sandbox, warnings} = makeSandbox({
    hint,
    root: makeRoot({url: "/dwar/admin/users.json"}),
    picker: {init(input, options) {
      initArgs = {input, options};
      return {destroy() {}};
    }}
  });
  runInline(script, sandbox);
  assert(hint.hidden === true, "happy path must leave the hint hidden");
  assert(warnings.length === 0, "happy path must not warn");
  assert(initArgs && initArgs.input && initArgs.input.kind === "input", "happy path must pass the input");
  assert(initArgs.options.url === "/dwar/admin/users.json", "happy path must pass the endpoint url");
  assert(initArgs.options.hiddenField && initArgs.options.hiddenField.kind === "hidden", "happy path must pass the hidden field");
}

try {
  const view = loadView();
  const script = extractInlineScript(view);
  checkStaticContract(view, script);
  scenarioMissingLibrary(script);
  scenarioMissingMarkup(script);
  scenarioMissingEndpoint(script);
  scenarioMissingInput(script);
  scenarioInitReturnsNoHandle(script);
  scenarioInitThrows(script);
  scenarioHappyPath(script);
  console.log("HINT-HARNESS-OK scenarios=7 missing-library missing-markup missing-endpoint missing-input no-handle init-throws happy-path");
} catch (error) {
  console.log(`HINT-HARNESS-FAIL ${error && error.message}`);
  process.exitCode = 1;
}
