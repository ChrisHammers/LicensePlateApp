import { defineConfig } from "vitest/config";

// Firestore security-rules suite. Requires the Firestore emulator:
//   npm run test:rules        (wraps `firebase emulators:exec --only firestore`)
// or, with an emulator already running on FIRESTORE_EMULATOR_HOST:
//   npx vitest run --config vitest.rules.config.ts
export default defineConfig({
  test: {
    include: ["rulesTests/**/*.test.ts"],
    testTimeout: 30000,
    hookTimeout: 60000,
    // One worker: every file shares the same emulator instance and project id.
    fileParallelism: false,
  },
});
