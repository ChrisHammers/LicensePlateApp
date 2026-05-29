"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mergeFairnessAckSeconds = mergeFairnessAckSeconds;
/**
 * Pure merge for per-user fairness UI watermark (Unix seconds). Used by `updateFairnessAckWatermark`.
 */
function mergeFairnessAckSeconds(existingSeconds, incomingSeconds) {
    return Math.max(existingSeconds, incomingSeconds);
}
//# sourceMappingURL=fairnessWatermarkMerge.js.map