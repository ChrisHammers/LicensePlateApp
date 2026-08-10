//
//  SpeechRecognizerOnDeviceTests.swift
//  LicensePlateAppTests
//
//  COPPA remediation F-4 / FR-45 — voice audio must stay on the device. Pins the two
//  pure pieces of that policy: the start-time decision and the request configuration.
//  Neither needs a microphone, a permission grant, or a live SFSpeechRecognizer.
//

import Foundation
import Speech
import Testing
@testable import LicensePlateApp

struct SpeechRecognizerOnDeviceTests {

    @Test func startsOnlyWhenOnDeviceRecognitionIsSupported() {
        #expect(
            SpeechRecognizer.startDecision(isAvailable: true, supportsOnDeviceRecognition: true)
            == .start
        )
    }

    /// No silent server fallback: an available recognizer without the on-device model is
    /// refused, and the caller gets the on-device-unavailable path, not `.start`.
    @Test func refusesToStartWhenOnDeviceRecognitionIsUnsupported() {
        #expect(
            SpeechRecognizer.startDecision(isAvailable: true, supportsOnDeviceRecognition: false)
            == .onDeviceUnavailable
        )
    }

    /// An unavailable recognizer keeps its own message regardless of on-device support.
    @Test func unavailableRecognizerReportsUnavailable() {
        #expect(
            SpeechRecognizer.startDecision(isAvailable: false, supportsOnDeviceRecognition: true)
            == .recognizerUnavailable
        )
        #expect(
            SpeechRecognizer.startDecision(isAvailable: false, supportsOnDeviceRecognition: false)
            == .recognizerUnavailable
        )
    }

    /// Every request the app creates is on-device. This is the assertion that would fail if
    /// someone made `requiresOnDeviceRecognition` conditional again.
    @Test func configureRequestForcesOnDeviceRecognition() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        #expect(request.requiresOnDeviceRecognition == false, "SFSpeechRecognitionRequest still defaults to server recognition")

        SpeechRecognizer.configureRequest(request)

        #expect(request.requiresOnDeviceRecognition == true)
        #expect(request.shouldReportPartialResults == true)
    }

    @Test func onDeviceUnavailableMessageIsLocalizedAndNonEmpty() {
        #expect(SpeechRecognizer.onDeviceUnavailableMessage.isEmpty == false)
    }
}
