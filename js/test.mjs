// The WebAssembly phonemizer held to the fixtures the Swift build wrote:
// every row must come out identical, glide (U+02B2) included.
//   node --test js/test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { open } from "./phonemizer.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const dataParent = join(root, "Sources/VoiceCore/Resources");
const rows = name => readFileSync(join(root, "Tests/VoiceCoreTests/Fixtures", name), "utf8")
  .split("\n").filter(line => line && !line.startsWith("#")).map(line => line.split("\t"));

test("English says what the Swift build says, word for word", async () => {
  const espeak = await open({ dataParent, voice: "en-us" });
  assert.match(espeak.version, /^1\.52/);
  for (const [text, ipa] of rows("en_us_phonemes.tsv")) assert.equal(espeak.phonemize(text, { dropFinalStop: true }), ipa, text);
});

test("Gateway Forge's calls are unchanged, with its respellings and no em-dash spacing", async () => {
  const gateway = await open({ dataParent, voice: "en-us", spacesEmDashes: false,
                               respellings: [["I-There", "Eye-There"], ["REBAL", "Reeball"]] });
  const calls = rows("gateway_forge_calls.tsv");
  assert.ok(calls.length > 300);
  let glides = 0;
  for (const [text, ipa] of calls) {
    assert.equal(gateway.phonemize(text, { dropFinalStop: true }), ipa, text);
    if (ipa.includes("ʲ")) glides += 1;
  }
  assert.ok(glides > 50, `the glide is in ${glides} rows`);
});

test("respellings and em dashes are options", async () => {
  const plain = await open({ dataParent, voice: "en-us" });
  const gateway = await open({ dataParent, voice: "en-us", spacesEmDashes: false,
                               respellings: [["I-There", "Eye-There"], ["REBAL", "Reeball"]] });
  assert.equal(gateway.phonemize("I-There"), plain.phonemize("Eye-There"));
  assert.equal(gateway.phonemize("quiet—and"), plain.phonemize("quiet and"));
  assert.notEqual(plain.phonemize("quiet—and"), plain.phonemize("quiet and"));
});
