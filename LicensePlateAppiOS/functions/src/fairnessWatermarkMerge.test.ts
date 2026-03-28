import { describe, it, expect } from "vitest";
import { mergeFairnessAckSeconds } from "./fairnessWatermarkMerge";

describe("mergeFairnessAckSeconds", () => {
  it("takes the greater of two values", () => {
    expect(mergeFairnessAckSeconds(10, 5)).toBe(10);
    expect(mergeFairnessAckSeconds(5, 10)).toBe(10);
    expect(mergeFairnessAckSeconds(0, 0)).toBe(0);
  });
});
