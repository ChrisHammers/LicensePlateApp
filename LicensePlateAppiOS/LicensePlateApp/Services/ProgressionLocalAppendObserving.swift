//
//  ProgressionLocalAppendObserving.swift
//  LicensePlateApp
//
//  Step 16 addendum — Notify when a gameplay activity event is durably appended locally (offline pending path).
//

import Foundation

@MainActor
protocol ProgressionLocalAppendObserving: AnyObject {
    func progressionDidCommitLocalActivityEvent(_ event: TripActivityEvent)
}
