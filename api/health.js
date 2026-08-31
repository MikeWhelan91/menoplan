export default function handler(_req, res) {
  const visionModel = process.env.OPENAI_VISION_MODEL?.trim() || null;
  const assistantModel = process.env.OPENAI_ASSISTANT_MODEL?.trim() || null;
  res.status(200).json({
    ok: true,
    service: "menoplan-ai-api",
    model: visionModel,
    modelConfigured: visionModel !== null,
    assistantModel,
    assistantModelConfigured: assistantModel !== null,
    imageDetail: process.env.OPENAI_IMAGE_DETAIL || "original",
    reasoningEffort: process.env.OPENAI_FSH_REASONING_EFFORT || "low"
  });
}
