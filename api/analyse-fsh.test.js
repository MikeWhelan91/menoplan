import { test } from "node:test";
import assert from "node:assert/strict";
import { normaliseResult, validatePayload } from "./analyse-fsh.js";

const base = {
  resultType: "elevated", certaintyPercentage: 85, controlLineDetected: true, testLineDetected: true,
  testControlRatio: 0.5, lineStrength: 0.5, imageQualityStatus: "good", explanation: "Visible lines.",
  observedLinePattern: "", nextBestAction: "", trendSummary: "", guidance: "", qualityNotes: [],
  controlLineDyeSignal: 100, visualStrengthBand: "halfToThreeQuarters"
};

test("the server owns the band from the ratio, with the app's thresholds", () => {
  assert.equal(normaliseResult({ ...base, testLineDyeSignal: 30, visualStrengthBand: "lessThanHalf" }).resultType, "low");
  assert.equal(normaliseResult({ ...base, testLineDyeSignal: 55 }).resultType, "borderline");
  assert.equal(normaliseResult({ ...base, testLineDyeSignal: 90, visualStrengthBand: "threeQuartersToNearlyEqual" }).resultType, "elevated");
  assert.equal(normaliseResult({ ...base, controlLineDetected: false, testLineDyeSignal: 90 }).resultType, "invalid");
});

test("returns every field the app decodes", () => {
  const result = normaliseResult({ ...base, testLineDyeSignal: 55 });
  for (const key of ["resultType", "confidencePercentage", "certaintyPercentage", "controlLineDetected", "testLineDetected",
    "testControlRatio", "lineStrength", "observedLinePattern", "nextBestAction", "imageQualityStatus", "explanation",
    "trendSummary", "guidance", "qualityNotes"]) {
    assert.ok(key in result, key);
  }
});

test("accepts the app's Look Again opinions", () => {
  for (const opinion of ["elevated", "borderline", "low", "notSure"]) {
    assert.equal(validatePayload({ imageBase64: "abc", userStatedOpinion: opinion }), null);
  }
});
