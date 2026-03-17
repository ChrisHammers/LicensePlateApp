//
//  DebugPersistenceFlags.swift
//  LicensePlateApp
//
//  DEBUG-only flags to force persistence failures for manual testing of error alerts.
//

import Foundation

#if DEBUG

enum DebugPersistenceOperation {
    case save
    case create
    case append
}

enum DebugForcedPersistenceError: Error, LocalizedError {
    case save
    case create
    case append

    var errorDescription: String? {
        switch self {
        case .save: return "Debug: forced failure (save)"
        case .create: return "Debug: forced failure (create)"
        case .append: return "Debug: forced failure (append)"
        }
    }
}

enum DebugPersistenceFlags {
    static let keyForSave = "DebugForcePersistenceSave"
    static let keyForCreate = "DebugForcePersistenceCreate"
    static let keyForAppend = "DebugForcePersistenceAppend"

    static func shouldForceFailure(for operation: DebugPersistenceOperation) -> Bool {
        let key: String
        switch operation {
        case .save: key = keyForSave
        case .create: key = keyForCreate
        case .append: key = keyForAppend
        }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func setForceFailure(_ enabled: Bool, for operation: DebugPersistenceOperation) {
        let key: String
        switch operation {
        case .save: key = keyForSave
        case .create: key = keyForCreate
        case .append: key = keyForAppend
        }
        UserDefaults.standard.set(enabled, forKey: key)
    }
}

#endif
