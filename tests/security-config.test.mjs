import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("Vercel applies the Redpen security-header baseline", async () => {
  const config = JSON.parse(await readFile("vercel.json", "utf8"));
  const headers = Object.fromEntries(
    config.headers[0].headers.map(({ key, value }) => [key, value]),
  );

  assert.equal(headers["X-Content-Type-Options"], "nosniff");
  assert.equal(headers["X-Frame-Options"], "DENY");
  assert.equal(headers["Referrer-Policy"], "no-referrer");
  assert.match(headers["Permissions-Policy"], /microphone=\(self\)/);
  assert.match(headers["Content-Security-Policy"], /frame-ancestors 'none'/);
  assert.match(headers["Content-Security-Policy"], /huggingface\.co/);
});

test("the remote speech model is pinned to an immutable revision", async () => {
  const worker = await readFile("src/whisper.worker.ts", "utf8");

  assert.match(worker, /const MODEL_REVISION = '[0-9a-f]{40}'/);
  assert.match(worker, /revision: MODEL_REVISION/);
});

test("the document uses the Redpen favicon instead of a starter asset", async () => {
  const html = await readFile("index.html", "utf8");
  const favicon = await readFile("public/favicon.svg", "utf8");
  const touchIcon = await readFile("public/apple-touch-icon.png");

  assert.match(html, /href="\/favicon\.svg"/);
  assert.match(html, /href="\/apple-touch-icon\.png"/);
  assert.match(favicon, /#ff2d2d/);
  assert.doesNotMatch(favicon, /#863bff/);
  assert.equal(touchIcon.subarray(1, 4).toString(), "PNG");
});
