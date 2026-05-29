"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.enforcedCallable = enforcedCallable;
const functions = require("firebase-functions");
function enforcedCallable(handler) {
    return functions
        .runWith({ enforceAppCheck: true })
        .https.onCall(handler);
}
//# sourceMappingURL=callableOptions.js.map