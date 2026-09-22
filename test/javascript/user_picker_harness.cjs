// Dev-only smoke harness for app/assets/javascripts/dwar/user_picker.js.
// No dependencies: node stdlib only (fs, path, vm). Run with:
//   node test/javascript/user_picker_harness.cjs
// Exit 0 + "HARNESS-OK" means debounce -> fetch -> render -> select ->
// hidden-field all behaved, including the stale-response guard. Any failure
// prints "HARNESS-FAIL" and exits non-zero. Executed in CI-by-proxy through
// test/javascript/user_picker_js_test.rb (skipped when node is unavailable).
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const ASSET = path.join(__dirname, "..", "..", "app", "assets", "javascripts", "dwar", "user_picker.js");

function makeElement(tag) {
  const el = {
    tagName: tag,
    children: [],
    style: {},
    attributes: {},
    listeners: {},
    value: "",
    textContent: "",
    parentElement: null,
    setAttribute(k, v) {
      this.attributes[k] = String(v);
    },
    getAttribute(k) {
      return this.attributes[k];
    },
    removeAttribute(k) {
      delete this.attributes[k];
    },
    addEventListener(type, fn) {
      (this.listeners[type] = this.listeners[type] || []).push(fn);
    },
    removeEventListener(type, fn) {
      this.listeners[type] = (this.listeners[type] || []).filter((f) => f !== fn);
    },
    appendChild(child) {
      this.children.push(child);
      child.parentElement = this;
      return child;
    },
    contains(node) {
      if (node === this) {
        return true;
      }
      return this.children.some((c) => c === node || (c.contains && c.contains(node)));
    },
    querySelector(selector) {
      if (selector === "[data-dwar-user-picker-list]") {
        return this.children.find((c) => c.attributes && ("data-dwar-user-picker-list" in c.attributes)) || null;
      }
      return null;
    },
    fire(type, event) {
      (this.listeners[type] || []).forEach((fn) => fn(event || {}));
    }
  };
  Object.defineProperty(el, "innerHTML", {
    get() {
      return this._html || "";
    },
    set(_v) {
      this.children = [];
      this._html = "";
    }
  });
  return el;
}

function makeDocument() {
  return {
    listeners: {},
    createElement(tag) {
      return makeElement(tag);
    },
    addEventListener(type, fn) {
      (this.listeners[type] = this.listeners[type] || []).push(fn);
    },
    removeEventListener(type, fn) {
      this.listeners[type] = (this.listeners[type] || []).filter((f) => f !== fn);
    }
  };
}

function loadPicker(fetchImpl) {
  const document = makeDocument();
  const sandbox = {
    document,
    fetch: fetchImpl,
    setTimeout,
    clearTimeout,
    encodeURIComponent,
    console
  };
  vm.runInNewContext(fs.readFileSync(ASSET, "utf8"), sandbox, {filename: "user_picker.js"});
  if (!sandbox.DwarUserPicker || typeof sandbox.DwarUserPicker.init !== "function") {
    throw new Error("DwarUserPicker.init not exported");
  }
  return {document, picker: sandbox.DwarUserPicker};
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function assert(cond, message) {
  if (!cond) {
    throw new Error(message);
  }
}

function makeDeferredFetch(log) {
  const pending = [];
  const calls = [];
  const fetch = (url, _opts) => {
    calls.push(url);
    return new Promise((resolve, reject) => {
      pending.push({url, resolve, reject});
    });
  };
  if (log) {
    log.calls = calls;
    log.pending = pending;
  }
  return {fetch, calls, pending};
}

function okJson(items) {
  return {ok: true, json: () => Promise.resolve(items)};
}

async function scenarioSelectFlow() {
  const log = {};
  const {fetch, calls, pending} = makeDeferredFetch(log);
  const {document, picker} = loadPicker(fetch);

  const input = makeElement("input");
  const hidden = makeElement("input");
  const list = makeElement("ul");
  // URL already carries a query string: the search term must join with &.
  const handle = picker.init(input, {url: "/dwar/admin/users.json?scope=all", hiddenField: hidden, list, debounceMs: 5});
  assert(handle && typeof handle.destroy === "function", "init returns a destroy handle");

  input.value = "al";
  input.fire("input");
  await sleep(30);
  assert(calls.length === 1, `expected 1 fetch after debounce, got ${calls.length}`);
  assert(
    calls[0] === "/dwar/admin/users.json?scope=all&q=al",
    `unexpected fetch url: ${calls[0]}`
  );

  pending[0].resolve(okJson([{id: 7, label: "Harness Hannah"}]));
  await sleep(10);
  assert(list.children.length === 1, `expected 1 rendered row, got ${list.children.length}`);
  assert(list.children[0].textContent === "Harness Hannah", "row shows the record label");

  list.children[0].fire("mousedown", {preventDefault() {}});
  assert(input.value === "Harness Hannah", "select fills the visible label");
  assert(hidden.value === "7", "select fills the hidden id");
  assert(list.children.length === 0, "select clears the list");

  handle.destroy();
  assert((document.listeners.click || []).length === 0, "destroy removes the document listener");
}

async function scenarioStaleGuard() {
  const {fetch, pending} = makeDeferredFetch();
  const {picker} = loadPicker(fetch);

  const input = makeElement("input");
  const hidden = makeElement("input");
  const list = makeElement("ul");
  const handle = picker.init(input, {url: "/dwar/admin/users.json", hiddenField: hidden, list, debounceMs: 5});

  input.value = "a";
  input.fire("input");
  await sleep(30);
  input.value = "ab";
  input.fire("input");
  await sleep(30);
  assert(pending.length === 2, `expected 2 in-flight requests, got ${pending.length}`);

  // Newer response lands first, then the stale one: stale must be ignored.
  pending[1].resolve(okJson([{id: 2, label: "Second"}]));
  await sleep(10);
  assert(list.children.length === 1 && list.children[0].textContent === "Second", "newest response renders");
  pending[0].resolve(okJson([{id: 1, label: "First"}]));
  await sleep(10);
  assert(list.children.length === 1 && list.children[0].textContent === "Second", "stale response ignored");

  handle.destroy();
}

async function scenarioEmptyAndFailure() {
  const {fetch, calls, pending} = makeDeferredFetch();
  const {picker} = loadPicker(fetch);

  const input = makeElement("input");
  const hidden = makeElement("input");
  const list = makeElement("ul");
  const handle = picker.init(input, {url: "/dwar/admin/users.json", hiddenField: hidden, list, debounceMs: 5});

  // Empty query clears without fetching and never throws.
  input.value = "";
  input.fire("input");
  await sleep(20);
  assert(calls.length === 0, "empty query issues no fetch");

  // Failed fetch clears to the empty state and never throws.
  input.value = "zz";
  input.fire("input");
  await sleep(30);
  assert(pending.length === 1, "failing query issues a fetch");
  pending[0].reject(new Error("network down"));
  await sleep(10);
  assert(list.children.length === 0, "failed fetch leaves an empty list");

  handle.destroy();
}

(async () => {
  try {
    await scenarioSelectFlow();
    await scenarioStaleGuard();
    await scenarioEmptyAndFailure();
    console.log("HARNESS-OK scenarios=3 debounce-fetch-render-select-hidden-field stale-guard empty-failure");
  } catch (error) {
    console.log(`HARNESS-FAIL ${error && error.message}`);
    process.exitCode = 1;
  }
})();
