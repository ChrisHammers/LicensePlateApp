//
//  SpeechRecognizer.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import Foundation
import Speech
import AVFoundation
import Combine

class SpeechRecognizer: ObservableObject {
    @Published var isListening = false
    /// True from engine start until first recognition result (or fallback timeout)
    @Published var isPreparing = false
    /// True from startListening until we're preparing/listening; prevents duplicate starts from repeated onChanged
    @Published var isStarting = false
    @Published var recognizedText = ""
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    
    /// Called when the mic is ready for input. Use for haptic and audio feedback.
    var onListeningStarted: (() -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    /// Create new instance per session—reusing causes tap/graph corruption (see AVAudioEngine_SpeechRecognition_Notes.md)
    private var audioEngine = AVAudioEngine()
    private var readyFallbackTask: Task<Void, Never>?
    /// Incremented each startListening; completions check this to avoid installing tap after a newer start
    private var startGeneration: Int = 0
    /// True after we install tap; used to safely remove only when we have one
    private var hasInstalledTap: Bool = false
    
    init(onListeningStarted: (() -> Void)? = nil) {
        self.onListeningStarted = onListeningStarted
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        //TODO: should we change this based on your region?
        Task { @MainActor in
            checkAuthorizationStatus()
        }
    }
    
    @MainActor
    func checkAuthorizationStatus() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }
    
    @MainActor
    func requestAuthorization() async {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        authorizationStatus = status
    }
    
    @MainActor
    func startListening() {
        guard authorizationStatus == .authorized else {
            errorMessage = "Speech recognition not authorized"
            return
        }
        
        guard let speechRecognizer = speechRecognizer else {
            errorMessage = "Speech recognizer not available"
            return
        }

        switch Self.startDecision(
            isAvailable: speechRecognizer.isAvailable,
            supportsOnDeviceRecognition: speechRecognizer.supportsOnDeviceRecognition
        ) {
        case .recognizerUnavailable:
            errorMessage = "Speech recognizer not available"
            return
        case .onDeviceUnavailable:
            errorMessage = Self.onDeviceUnavailableMessage
            return
        case .start:
            break
        }

        // Stop any existing recognition
        stopListening()
        isStarting = true
        startGeneration += 1
        let generation = startGeneration
        
        // Clear previous text
        recognizedText = ""
        errorMessage = nil
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Unable to create recognition request"
            isStarting = false
            return
        }
        
        Self.configureRequest(recognitionRequest)
        // Continue setup immediately; sound plays only when Listening (via onListeningStarted)
        continueStartListening(recognitionRequest: recognitionRequest, generation: generation)
    }
    
    @MainActor
    private func continueStartListening(recognitionRequest: SFSpeechAudioBufferRecognitionRequest, generation: Int) {
        guard generation == startGeneration else { isStarting = false; return }
        guard isStarting else { return } // User released before setup finished
        guard let speechRecognizer = speechRecognizer else { isStarting = false; return }
        isStarting = false
        // Set up audio session FIRST—inputNode format is undefined until session is active
        let audioSession = AVAudioSession.sharedInstance()
        do {
          try audioSession.setCategory(.playAndRecord, options: [.defaultToSpeaker, .duckOthers, .allowBluetoothHFP])
          try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)  // Allow haptics + sounds while mic is active
          try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio session setup failed: \(error.localizedDescription)"
            isStarting = false
            return
        }
        
        // New engine per session—avoids tap/graph corruption from reuse (see docs)
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        // Use inputFormat for mic tap (SO 41805381); validate—invalid format causes crash
        var recordingFormat = inputNode.inputFormat(forBus: 0)
        if recordingFormat.sampleRate <= 0 || recordingFormat.channelCount == 0 {
            recordingFormat = inputNode.outputFormat(forBus: 0)
        }
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            errorMessage = "Microphone not available (format invalid)"
            isStarting = false
            return
        }
        let format = recordingFormat
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak recognitionRequest] buffer, _ in
            recognitionRequest?.append(buffer)
        }
        hasInstalledTap = true
        
        audioEngine.prepare()
        // prepare() can deallocate nodes—ensure inputNode exists before start()
        _ = audioEngine.inputNode
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if let error = error {
                    let errDesc = error.localizedDescription.lowercased()
                    // Ignore "no speech detected" when we got results—spurious final error after successful transcription
                    if errDesc.contains("no speech detected") && !self.recognizedText.isEmpty {
                        return
                    }
                    // Ignore kAFAssistantErrorDomain (1101, 1107)—framework logs these even when transcription succeeds
                    if (error as NSError).domain.contains("kAFAssistantErrorDomain") {
                        return
                    }
                    print(error.localizedDescription)
                    self.errorMessage = "Recognition error: \(error.localizedDescription)"
                    self.stopListening()
                    return
                }
                
                if let result = result {
                    self.recognizedText = result.bestTranscription.formattedString
                    
                    // First result = speech recognizer is ready, show "Listening" and trigger feedback
                    if !self.isListening {
                        self.readyFallbackTask?.cancel()
                        self.readyFallbackTask = nil
                        self.isPreparing = false
                        self.isListening = true
                        self.onListeningStarted?()
                    }
                    
                    if result.isFinal {
                        self.stopListening()
                    }
                }
            }
        }
        
        // Start audio engine
        do {
            try audioEngine.start()
            isPreparing = true
            // Fallback: if no result in 1.5 sec (user silent), show "Listening" anyway
            readyFallbackTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                if !self.isListening {
                    self.isPreparing = false
                    self.isListening = true
                    self.onListeningStarted?()
                }
                self.readyFallbackTask = nil
            }
        } catch {
            errorMessage = "Audio engine failed to start: \(error.localizedDescription)"
            isStarting = false
            stopListening()
        }
    }
    
    @MainActor
    func stopListening() {
        readyFallbackTask?.cancel()
        readyFallbackTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        audioEngine.stop()
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInstalledTap = false
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Error stopping AVAudioSession")
        }
        
        // Play stop sound with ambient session (recording session is now inactive)
        if isListening || isPreparing {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.ambient, options: [.mixWithOthers])
                try session.setActive(true)
                FeedbackService.shared.stopRecording()
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            } catch { /* ignore */ }
        }
        
        isListening = false
        isPreparing = false
        isStarting = false
    }
    
    deinit {
        // Clean up resources without MainActor isolation
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInstalledTap {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }
}

// MARK: - On-device only (COPPA remediation F-4 / FR-45)

/// Voice audio must never leave the device. `SFSpeechRecognizer` defaults to server-backed
/// recognition, which would upload the microphone stream — including a child's voice — to
/// Apple. These two pure helpers are the whole policy: decide before starting, and configure
/// every request the same way. They are static so the rule is unit-testable without a mic.
extension SpeechRecognizer {

    /// Outcome of the pre-flight check in `startListening()`.
    enum StartDecision: Equatable {
        case start
        case recognizerUnavailable
        /// The on-device model is missing for this locale. We surface the error rather than
        /// silently falling back to server recognition.
        case onDeviceUnavailable
    }

    static func startDecision(isAvailable: Bool, supportsOnDeviceRecognition: Bool) -> StartDecision {
        guard isAvailable else { return .recognizerUnavailable }
        guard supportsOnDeviceRecognition else { return .onDeviceUnavailable }
        return .start
    }

    static var onDeviceUnavailableMessage: String {
        "Voice needs on-device speech recognition, which isn't ready on this device. Use the List tab to add plates.".localized
    }

    /// Single place that configures a recognition request. `requiresOnDeviceRecognition` is
    /// mandatory, never conditional — `startDecision` has already refused the unsupported case.
    static func configureRequest(_ request: SFSpeechAudioBufferRecognitionRequest) {
        request.shouldReportPartialResults = true
        // COPPA rationale: this is what keeps a child's voice out of COPPA-regulated
        // "online contact information" collection in the first place — server-backed
        // recognition would stream raw microphone audio to Apple. Must stay
        // unconditional; see `SpeechRecognizerOnDeviceTests.configureRequestForcesOnDeviceRecognition`.
        request.requiresOnDeviceRecognition = true
    }
}

