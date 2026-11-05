import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { stripTypeScriptTypes } from "node:module";
import { EventEmitter } from "node:events";
import vm from "node:vm";
import path from "node:path";
import crypto from "node:crypto";
import os from "node:os";

// Exercise the actual socket framing and handler without touching running Pi
// sessions, filesystem manifests, or the global latest-session symlink.
let accept;
const server = new EventEmitter();
server.listen = (_path, cb) => cb();
server.close = () => {};
const fs = Object.fromEntries(["mkdirSync", "unlinkSync", "symlinkSync", "writeFileSync"].map(k => [k, () => {}]));
fs.readlinkSync = () => "not-our-socket";
const source = stripTypeScriptTypes(readFileSync(new URL("../index.ts", import.meta.url), "utf8"))
  .replace(/^import .*;\n/gm, "")
  .replace("export default function", "globalThis.extension = function");
const sandbox = { net: { createServer: cb => { accept = cb; return server; } }, fs, os, path, crypto,
  process: { platform: "linux", pid: 999999, on() {}, stdout: { write() {} } } };
vm.runInNewContext(source, sandbox);
const handlers = {};
const submitted = [];
sandbox.extension({ on: (name, cb) => { handlers[name] = cb; }, registerCommand() {},
  sendUserMessage: (...args) => submitted.push(args) });
let draft = "Already typed question";
let writes = 0;
const ctx = { cwd: "/test", mode: "tui", ui: {
  getEditorText: () => draft,
  setEditorText: text => { draft = text; writes++; },
  notify() {},
} };
await handlers.session_start({}, ctx);
const conn = new EventEmitter();
const responses = [];
conn.write = line => responses.push(JSON.parse(line));
accept(conn);
const send = msg => conn.emit("data", Buffer.from(JSON.stringify(msg) + "\n"));

// Fragmented messages and multiple messages per chunk both work.
const first = JSON.stringify({ type: "append_draft", message: "First snippet" }) + "\n";
conn.emit("data", Buffer.from(first.slice(0, 12)));
assert.equal(writes, 0);
conn.emit("data", Buffer.from(first.slice(12)));
conn.emit("data", Buffer.from(JSON.stringify({ type: "append_draft", message: "Second snippet" }) + "\n" + JSON.stringify({ type: "ping" }) + "\n"));
assert.equal(draft, "Already typed question\n\nFirst snippet\n\nSecond snippet\n\n");
assert.equal(submitted.length, 0, "Appending must never start or queue a turn");
assert.equal(responses.at(-1).type, "pong");

const saved = draft;
for (const message of ["", "   ", null, 12]) {
  send({ type: "append_draft", message });
  assert.equal(responses.at(-1).ok, false);
  assert.equal(draft, saved);
}
for (const mode of ["rpc", "print", "json"]) {
  ctx.mode = mode;
  send({ type: "append_draft", message: "Must not replace a draft" });
  assert.equal(responses.at(-1).ok, false);
  assert.equal(draft, saved);
}
ctx.mode = "tui";
draft = "";
send({ type: "append_draft", message: "你好 🦊\n```lua\nx = 1\n```" });
assert.equal(draft, "你好 🦊\n```lua\nx = 1\n```\n\n");
assert.equal(submitted.length, 0);
send({ type: "prompt", message: "Existing send behavior" });
assert.equal(submitted.length, 1);
assert.equal(submitted[0][0], "Existing send behavior");
await handlers.session_shutdown();
console.log("Draft protocol tests passed");
