import { defineConfig } from "vitest/config";

// Default unit-test run: pure-module and fakeFirestore suites under src/ only.
// The Firestore-rules suite (rulesTests/) needs the emulator and runs separately
// via `npm run test:rules` (see vitest.rules.config.ts).
export default defineConfig({
  test: {
    include: ["src/**/*.test.ts"],
  },
});
