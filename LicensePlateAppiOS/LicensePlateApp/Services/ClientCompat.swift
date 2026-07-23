//
//  ClientCompat.swift
//  LicensePlateApp
//
//  Baked-in client↔server protocol floor. Bump only when this binary can no
//  longer safely talk to the previous backend contract.
//

import Foundation

enum ClientCompat {
    /// Current client compatibility version shipped with this binary.
    static let current = 1
}
