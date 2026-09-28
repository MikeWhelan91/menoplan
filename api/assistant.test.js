import { test } from "node:test";
import assert from "node:assert/strict";
import { makeAssistantRequest, validatePayload, SUGGESTION_KINDS } from "./assistant.js";

// The shape MenoPlan's AssistantService actually sends (AssistantRequest).
const appPayload = {
  message: "Why am I so tired?",
  userSafetyId: "abc",
  conversation: [{ role: "user", text: "Hi" }],
  recentScans: [{ date: "2026-09-27", testType: "ovulation", resultType: "borderline", certaintyPercentage: 80,
    confidencePercentage: 80, lineStrength: 0.4, testControlRatio: 0.55, analysisMode: "aiQuickCheck", notes: "", autoEnhancementSummary: "" }],
  reminders: [],
  userContext: { menopauseStage: "perimenopause", trackingFocus: "ovulation", focusSymptoms: ["Sleep"], dailyTrackingSummaries: [] }
};

test("accepts the app's payload", () => {
  assert.equal(validatePayload(appPayload), null);
  for (const mode of ["resultNarrative", "weeklyDigest", "compare"]) {
    assert.equal(validatePayload({ ...appPayload, mode }), null);
  }
});

test("rejects what the app never sends", () => {
  assert.equal(validatePayload({ ...appPayload, recentScans: undefined }), "Missing recentScans");
  assert.equal(validatePayload({ ...appPayload, mode: "progression" }), "Invalid mode");
  assert.equal(validatePayload({ ...appPayload, reminders: Array(9).fill({}) }), "Too many reminders");
});

test("chat gets suggestions; narrative modes don't", () => {
  const chat = makeAssistantRequest(appPayload, "m");
  assert.deepEqual(chat.text.format.schema.properties.suggestions.items.properties.kind.enum, SUGGESTION_KINDS);
  const narrative = makeAssistantRequest({ ...appPayload, mode: "resultNarrative" }, "m");
  assert.equal(narrative.text.format.schema.properties.suggestions, undefined);
  assert.match(narrative.input[0].content[0].text, /home FSH test/);
  assert.ok(chat.prompt_cache_key.length <= 64);
});
