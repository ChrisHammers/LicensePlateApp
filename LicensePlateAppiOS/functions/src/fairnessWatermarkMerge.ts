/**
 * Pure merge for per-user fairness UI watermark (Unix seconds). Used by `updateFairnessAckWatermark`.
 */
export function mergeFairnessAckSeconds(existingSeconds: number, incomingSeconds: number): number {
  return Math.max(existingSeconds, incomingSeconds);
}
