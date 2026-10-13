import { test } from "node:test";
import assert from "node:assert/strict";
import { persistBrowserPreference } from "./browser_preferences.mjs";

function browser(protocol = "https:") {
  const writes = [];
  globalThis.document = { set cookie(value) { writes.push(value); } };
  globalThis.location = { protocol };
  globalThis.localStorage = { setItem() {} };
  return writes;
}

test("HTTPS preferences use separate host-only Secure cookies", () => {
  const writes = browser();
  persistBrowserPreference("theme", "dark");
  persistBrowserPreference("locale", "nl");
  assert.deepEqual(writes, [
    "_ocl_theme=dark; Path=/; Max-Age=31536000; SameSite=Lax; Secure",
    "_ocl_locale=nl; Path=/; Max-Age=31536000; SameSite=Lax; Secure",
  ]);
});

test("blocked localStorage does not prevent the server-render cookie", () => {
  const writes = browser("http:");
  globalThis.localStorage.setItem = () => { throw new Error("blocked"); };
  persistBrowserPreference("theme", "light");
  assert.equal(writes.length, 1);
  assert.ok(writes[0].startsWith("_ocl_theme=light;"));
  assert.ok(!writes[0].includes("Secure"));
});

test("unknown names and values cannot inject cookie attributes or credentials", () => {
  const writes = browser();
  persistBrowserPreference("user_token", "credential");
  persistBrowserPreference("theme", "dark; Domain=example.com");
  persistBrowserPreference("locale", "fr");
  assert.deepEqual(writes, []);
});

test("blocked cookies do not break preference updates", () => {
  browser();
  globalThis.document = { set cookie(_) { throw new Error("blocked"); } };
  let saved;
  globalThis.localStorage.setItem = (key, value) => { saved = [key, value]; };
  assert.doesNotThrow(() => persistBrowserPreference("locale", "nl"));
  assert.deepEqual(saved, ["openchesslab:locale", "nl"]);
});
