const PROMPT_VERSION = "menoplan-fsh-v1";
const OPENAI_TIMEOUT_MS = 40000;
const IMAGE_QUALITY_VALUES = ["good", "tooDark", "overexposed", "blurry", "hardToDetect", "poor"];

// FSH home tests read almost identically to an ovulation LH strip: a
// control line and a test line, compared by relative darkness. There is no
// guided-capture viewport guaranteeing a fixed left/right orientation, so
// this prompt deliberately identifies C and T by their printed labels on
// the device housing rather than by position — most FSH/menopause test
// cassettes print "C" and "T" directly next to their result window for
// exactly this reason.
const FSH_PROMPT = `
Read one home FSH (follicle-stimulating hormone) menopause test from the user's photo. This is a two-line test cassette or strip, read by comparing the relative darkness of a test line against a control line — mechanically the same read as an ovulation LH test, not a pregnancy test.

Use only visible pixels. The live result window is a recessed strip or membrane set into the device housing. Printed text, icons, and reference diagrams on the surrounding plastic are never inside that recessed window — locate the live result window first, by its physical shape and texture, before looking for any marks.

Most FSH test devices print the letters "C" (control) and "T" (test) directly beside the result window, next to each respective line position. Locate these printed letters first and use them to identify which physical dye mark is the control line and which is the test line. Do not assume a fixed left-to-right order — orientation varies by brand and by how the photo was framed. If no printed C/T labels are visible, use the test's own instructional legend or diagram (if visible) to determine which position is control and which is test; if neither is available, return unclear rather than guessing.

Confirm a physical FSH/menopause test and its live result membrane/window are visible and readable. If not, return unclear.

Find control first: locate the line at the position labelled C. Verify it is a genuine localized dye band, not a shadow, seam, or printed mark. If no credible control line is present at the labelled C position, return invalid.

After locating C, find T at its own labelled position. Do not swap the pair based on relative darkness — T may be darker, lighter, or equal to C.

Measure dye signal, not raw pixel darkness. For each located line, compare it with the immediately adjacent blank membrane on both sides and subtract that local background. Ignore the membrane's base tint, shadows, and overall exposure.

Compare the located T directly with the located C and select visualStrengthBand before estimating a number: absent, lessThanHalf, halfToThreeQuarters, threeQuartersToNearlyEqual, or equalOrDarker. This direct visual comparison is the primary observation.

Put both lines on one relative scale. Set controlLineDyeSignal to 100 for a readable control line. Set testLineDyeSignal to T's visible background-corrected strength relative to C. Set it to 0 only when no localized T-line dye is visible.

Report testControlRatio as testLineDyeSignal divided by controlLineDyeSignal. Keep the ratio inside the selected visualStrengthBand.

Return:
- low when the test line is absent or clearly much lighter than control (ratio below 0.40). This is the pattern typically seen well before a hormonal transition.
- borderline when the test line is visible but still lighter than control (ratio 0.40 to below 0.75).
- elevated when the test line is close to or as dark as control (ratio 0.75 or above). This is the pattern some home FSH tests describe as a possible indicator of perimenopause or menopause — never state this as a diagnosis.
- invalid when the required control line is absent.
- unclear when the crop, image quality, line identification, or darkness comparison is not reliable enough to score.

Ratio calibration anchors after local-background subtraction:
- 0.00: no localized test-line dye.
- about 0.15–0.30: trace or very faint test line.
- about 0.40–0.65: clearly visible test line, roughly two-fifths to two-thirds as strong as control.
- about 0.75–0.90: test line close to, but still visibly lighter than, control.
- about 1.00: approximately equal dye signal; above 1.00 means test line is stronger than control.

This is a single visual reading of one test strip, not a hormone measurement or a diagnosis. FSH levels vary naturally day to day, and one reading cannot establish a trend or confirm any stage of menopause. Keep the explanation to one short, calm, customer-facing sentence describing only what is visible; do not narrate your reasoning process or mention printed reference material.

Also provide concise customer-facing support fields, all brief, calm, and strictly non-diagnostic: observedLinePattern describes only what is visibly different about the two lines; nextBestAction gives one practical next step (for example, testing again in a few days, or bringing this reading to a clinician alongside symptoms); guidance explains the useful context without ever claiming this result confirms or rules out perimenopause or menopause — always frame it as one data point to discuss with a healthcare professional alongside symptoms and history; trendSummary must say a single image cannot establish a trend and that spacing readings out over time gives a fuller picture.

Do not mistake plastic edges, glare, printed examples, packaging, printed legend icons, or background texture for a result. This is a visual reference reading, not a medical diagnosis, and must never be presented as one.
`.trim();

const COMMON_PROPERTIES = {
  certaintyPercentage: {
    type: "integer",
    minimum: 0,
    maximum: 100,
    description: "How readable and visually certain this image-based classification is; not medical certainty."
  },
  controlLineDetected: { type: "boolean" },
  testLineDetected: { type: "boolean" },
  testControlRatio: {
    type: "number",
    minimum: 0,
    maximum: 2,
    description: "Approximate visible test-line strength divided by control-line strength."
  },
  lineStrength: {
    type: "number",
    minimum: 0,
    maximum: 1,
    description: "Approximate absolute visibility of the test line."
  },
  imageQualityStatus: {
    type: "string",
    enum: IMAGE_QUALITY_VALUES
  },
  explanation: {
    type: "string",
    minLength: 12,
    maxLength: 220,
    description: "Briefly state exactly what is visible and why that supports the classification."
  },
  observedLinePattern: { type: "string", minLength: 0, maxLength: 180 },
  nextBestAction: { type: "string", minLength: 0, maxLength: 180 },
  trendSummary: { type: "string", minLength: 0, maxLength: 180 },
  guidance: { type: "string", minLength: 0, maxLength: 320 },
  qualityNotes: {
    type: "array",
    items: { type: "string", maxLength: 140 },
    maxItems: 2
  }
};

const FSH_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    resultType: {
      type: "string",
      enum: ["low", "borderline", "elevated", "unclear", "invalid"]
    },
    testLineDyeSignal: {
      type: "number",
      minimum: 0,
      maximum: 200,
      description: "Background-corrected test-line dye signal on the same relative scale as controlLineDyeSignal."
    },
    controlLineDyeSignal: {
      type: "number",
      minimum: 0,
      maximum: 200,
      description: "Background-corrected control-line dye signal, normalized to 100 when the control is readable."
    },
    visualStrengthBand: {
      type: "string",
      enum: ["absent", "lessThanHalf", "halfToThreeQuarters", "threeQuartersToNearlyEqual", "equalOrDarker"],
      description: "Direct visual comparison of the background-corrected T line against C, chosen before numeric estimation."
    },
    ...COMMON_PROPERTIES
  },
  required: [
    "resultType",
    "testLineDyeSignal",
    "controlLineDyeSignal",
    "visualStrengthBand",
    "certaintyPercentage",
    "controlLineDetected",
    "testLineDetected",
    "testControlRatio",
    "lineStrength",
    "imageQualityStatus",
    "explanation",
    "observedLinePattern",
    "nextBestAction",
    "trendSummary",
    "guidance",
    "qualityNotes"
  ]
};

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const configuredToken = process.env.MENOPLAN_API_SHARED_SECRET;
  if (configuredToken && req.headers["x-menoplan-client-token"] !== configuredToken) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  if (!process.env.OPENAI_API_KEY) {
    return res.status(500).json({ error: "OPENAI_API_KEY is not configured" });
  }

  const model = process.env.OPENAI_VISION_MODEL?.trim();
  if (!model) {
    return res.status(500).json({ error: "OPENAI_VISION_MODEL is not configured" });
  }

  try {
    const payload = typeof req.body === "string" ? JSON.parse(req.body) : req.body;
    const validationError = validatePayload(payload);
    if (validationError) {
      return res.status(400).json({ error: validationError });
    }

    const openAI = await callOpenAI(payload, model);
    logUsage(openAI.data);
    if (!openAI.response.ok) {
      return res.status(openAI.response.status).json({
        error: "OpenAI request failed",
        detail: openAI.data?.error?.message || "Unknown OpenAI error"
      });
    }

    const extracted = extractStructuredResult(openAI.data);
    if (extracted.refusal) {
      return res.status(502).json({ error: "Analysis could not read this image right now." });
    }
    if (extracted.incomplete) {
      return res.status(502).json({ error: "OpenAI returned an incomplete response", detail: extracted.incomplete });
    }
    if (!extracted.text && !extracted.parsed) {
      return res.status(502).json({
        error: "OpenAI returned no structured result",
        detail: describeUnexpectedResponse(openAI.data)
      });
    }

    const rawResult = extracted.parsed || JSON.parse(extracted.text);
    return res.status(200).json({
      ...normaliseResult(rawResult),
      model: openAI.data.model || model,
      promptVersion: PROMPT_VERSION
    });
  } catch (error) {
    if (Number.isInteger(error?.statusCode)) {
      return res.status(error.statusCode).json({ error: "AI analysis failed", detail: error.message });
    }
    return res.status(500).json({ error: "AI analysis failed", detail: error.message });
  }
}

const USER_OPINION_VALUES = ["low", "borderline", "elevated", "notSure"];

function validatePayload(payload) {
  if (!payload || typeof payload !== "object") return "Missing JSON body";
  if (!payload.imageBase64 || typeof payload.imageBase64 !== "string") return "Missing imageBase64";
  if (payload.imageBase64.length > 6_000_000) return "Image payload is too large";
  if (payload.userStatedOpinion != null && !USER_OPINION_VALUES.includes(payload.userStatedOpinion)) {
    return "Invalid userStatedOpinion";
  }
  return null;
}

function makeOpenAIRequest(payload, model) {
  // "Manual Check" in the app lets the user brighten/contrast-adjust the photo
  // themselves and optionally say what they think they see before Luna reads
  // it. This is fallible, non-authoritative context the model must weigh, not
  // adopt as its classification without independent visual confirmation.
  const opinionText = payload.userStatedOpinion && payload.userStatedOpinion !== "notSure"
    ? `\n\nThe user manually brightened/adjusted this photo themselves before sending it and their own impression of the result is "${payload.userStatedOpinion}". Treat this exactly like the local pixel analysis: fallible, non-authoritative context to weigh, never adopted as your classification without independently confirming it against the image.`
    : "";

  return {
    model,
    prompt_cache_key: `menoplan-fsh-${PROMPT_VERSION}`,
    reasoning: {
      effort: process.env.OPENAI_FSH_REASONING_EFFORT || "low"
    },
    input: [
      {
        role: "system",
        content: [{ type: "input_text", text: FSH_PROMPT }]
      },
      {
        role: "user",
        content: [
          {
            type: "input_text",
            text: `Read this FSH menopause test from the single user photo below. Independently locate the control and test line positions from the printed C/T labels or legend visible on the device.${opinionText}`
          },
          {
            type: "input_image",
            image_url: `data:image/jpeg;base64,${payload.imageBase64}`,
            detail: process.env.OPENAI_IMAGE_DETAIL || "original"
          }
        ]
      }
    ],
    text: {
      verbosity: "low",
      format: {
        type: "json_schema",
        name: "menoplan_fsh_result",
        strict: true,
        schema: FSH_SCHEMA
      }
    }
  };
}

async function callOpenAI(payload, model) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), OPENAI_TIMEOUT_MS);

  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${process.env.OPENAI_API_KEY}`,
        "Content-Type": "application/json",
        "OpenAI-Safety-Identifier": "menoplan-anonymous"
      },
      body: JSON.stringify(makeOpenAIRequest(payload, model)),
      signal: controller.signal
    });
    return { response, data: await response.json() };
  } catch (error) {
    if (error?.name === "AbortError") {
      const timeoutError = new Error("OpenAI request timed out");
      timeoutError.statusCode = 504;
      throw timeoutError;
    }
    throw error;
  } finally {
    clearTimeout(timeoutId);
  }
}

function extractStructuredResult(data) {
  if (data?.status === "incomplete") {
    return {
      text: null,
      parsed: null,
      refusal: null,
      incomplete: JSON.stringify(data.incomplete_details || { reason: "unknown" })
    };
  }

  if (typeof data.output_text === "string" && data.output_text.trim()) {
    return { text: data.output_text, parsed: null, refusal: null, incomplete: null };
  }

  for (const item of data.output || []) {
    if (item?.type !== "message") continue;
    for (const content of item.content || []) {
      if (content?.type === "refusal" && typeof content.refusal === "string") {
        return { text: null, parsed: null, refusal: content.refusal, incomplete: null };
      }
      if (content?.parsed && typeof content.parsed === "object") {
        return { text: null, parsed: content.parsed, refusal: null, incomplete: null };
      }
      if (content?.type === "output_text" && typeof content.text === "string" && content.text.trim()) {
        return { text: content.text, parsed: null, refusal: null, incomplete: null };
      }
    }
  }

  return { text: null, parsed: null, refusal: null, incomplete: null };
}

function describeUnexpectedResponse(data) {
  const status = data?.status || "unknown";
  const outputTypes = Array.isArray(data?.output)
    ? data.output.map(item => item?.type || "unknown").join(", ")
    : "none";
  return `status=${status}; output=${outputTypes}`;
}

function logUsage(data) {
  const usage = data?.usage;
  if (!usage) return;
  console.info("menoplan_fsh_ai_usage", JSON.stringify({
    promptVersion: PROMPT_VERSION,
    model: data?.model || "unknown",
    inputTokens: usage.input_tokens ?? null,
    cachedInputTokens: usage.input_tokens_details?.cached_tokens ?? null,
    outputTokens: usage.output_tokens ?? null,
    reasoningTokens: usage.output_tokens_details?.reasoning_tokens ?? null,
    totalTokens: usage.total_tokens ?? null
  }));
}

function normaliseResult(result) {
  const allowedResults = ["low", "borderline", "elevated", "unclear", "invalid"];
  let resultType = allowedResults.includes(result.resultType) ? result.resultType : "unclear";
  let certainty = clampInteger(result.certaintyPercentage, 0, 100);
  let testControlRatio = clampNumber(result.testControlRatio, 0, 2);
  const lineStrength = clampNumber(result.lineStrength, 0, 1);
  let testLineDetected = Boolean(result.testLineDetected);
  const cleanText = (value, limit) => typeof value === "string" ? value.trim().slice(0, limit) : "";
  let explanation = typeof result.explanation === "string" && result.explanation.trim()
    ? result.explanation.trim().slice(0, 220)
    : "The image-based reading is unclear.";
  let observedLinePattern = cleanText(result.observedLinePattern, 180);
  let nextBestAction = cleanText(result.nextBestAction, 180);
  let trendSummary = cleanText(result.trendSummary, 180);
  let guidance = cleanText(result.guidance, 320);
  const qualityNotes = Array.isArray(result.qualityNotes)
    ? result.qualityNotes.filter(note => typeof note === "string").slice(0, 2).map(note => note.trim().slice(0, 140))
    : [];
  const controlLineDetected = Boolean(result.controlLineDetected);
  const imageQualityStatus = IMAGE_QUALITY_VALUES.includes(result.imageQualityStatus)
    ? result.imageQualityStatus
    : "hardToDetect";

  const testLineDyeSignal = clampNumber(result.testLineDyeSignal, 0, 200);
  const controlLineDyeSignal = clampNumber(result.controlLineDyeSignal, 0, 200);
  if (controlLineDetected && controlLineDyeSignal > 0) {
    testControlRatio = clampNumber(testLineDyeSignal / controlLineDyeSignal, 0, 2);
  }

  const visualBandRanges = {
    absent: { min: 0, max: 0.02, fallback: 0 },
    lessThanHalf: { min: 0.03, max: 0.49, fallback: 0.30 },
    halfToThreeQuarters: { min: 0.50, max: 0.74, fallback: 0.62 },
    threeQuartersToNearlyEqual: { min: 0.75, max: 0.94, fallback: 0.84 },
    equalOrDarker: { min: 0.95, max: 2, fallback: 1.00 }
  };
  const visualBand = visualBandRanges[result.visualStrengthBand];
  if (visualBand && (testControlRatio < visualBand.min || testControlRatio > visualBand.max)) {
    testControlRatio = visualBand.fallback;
  }

  // The server owns the final band so a prose classification from the model
  // can never disagree with its own reported ratio.
  if (!controlLineDetected) {
    resultType = "invalid";
    testLineDetected = false;
  } else if (resultType !== "unclear") {
    if (!testLineDetected || testControlRatio < 0.40) {
      resultType = "low";
    } else if (testControlRatio < 0.75) {
      resultType = "borderline";
    } else {
      resultType = "elevated";
    }
  } else {
    certainty = Math.min(certainty, 60);
  }

  if (!["invalid", "unclear"].includes(resultType)
    && ["tooDark", "overexposed", "blurry", "poor"].includes(imageQualityStatus)) {
    certainty = Math.min(certainty, 70);
  }

  const boundaryDistance = Math.min(
    Math.abs(testControlRatio - 0.40),
    Math.abs(testControlRatio - 0.75)
  );
  if (!["invalid", "unclear"].includes(resultType) && boundaryDistance <= 0.05) {
    certainty = Math.min(certainty, 72);
  }

  const fshCopy = {
    low: "No test line, or a much fainter test line than control — this pattern is typically seen outside a hormonal transition.",
    borderline: "A visible but lighter test line than control. Consider testing again in a few days.",
    elevated: "The test line is close to or as dark as the control line — some home FSH tests describe this pattern as a possible indicator worth discussing with a clinician.",
    invalid: "The control line is missing, so use a new test and follow its instructions.",
    unclear: "The lines cannot be compared clearly. Retake the photo in even light."
  };
  if (!explanation || explanation === "The image-based reading is unclear.") {
    explanation = fshCopy[resultType];
  }
  if (!observedLinePattern) {
    observedLinePattern = resultType === "invalid"
      ? "The required control line is not visible."
      : resultType === "unclear"
        ? "The test and control lines cannot be compared reliably."
        : resultType === "low" && !testLineDetected
          ? "The control line is visible and no distinct test line is visible."
          : `The estimated test-to-control line ratio is ${testControlRatio.toFixed(2)}.`;
  }
  if (!trendSummary) trendSummary = "One reading cannot establish a trend. Spacing readings out over time gives a fuller picture.";
  if (!nextBestAction) nextBestAction = resultType === "elevated"
    ? "Bring this reading and your recent symptoms to a healthcare professional."
    : resultType === "borderline"
      ? "Test again in a few days and keep logging your symptoms."
      : "Continue your normal tracking routine.";
  if (!guidance) guidance = "This is one data point. FSH levels vary naturally day to day — discuss your symptoms and full test series with a healthcare professional rather than relying on a single reading.";

  return {
    resultType,
    confidencePercentage: certainty,
    certaintyPercentage: certainty,
    controlLineDetected,
    testLineDetected,
    testControlRatio,
    lineStrength,
    observedLinePattern,
    nextBestAction,
    imageQualityStatus,
    explanation,
    trendSummary,
    guidance,
    qualityNotes
  };
}

function clampInteger(value, min, max) {
  return Math.min(max, Math.max(min, Number.isFinite(value) ? Math.round(value) : min));
}

function clampNumber(value, min, max) {
  return Math.min(max, Math.max(min, Number.isFinite(value) ? value : min));
}

export {
  FSH_PROMPT,
  PROMPT_VERSION,
  makeOpenAIRequest,
  normaliseResult,
  validatePayload
};
