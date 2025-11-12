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
    @Published var recognizedText = ""
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    init() {
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
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognizer not available"
            return
        }
        
        // Stop any existing recognition
        stopListening()
        
        // Clear previous text
        recognizedText = ""
        errorMessage = nil
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Unable to create recognition request"
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Set up audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio session setup failed: \(error.localizedDescription)"
            return
        }
        
        // Prepare audio engine first to ensure format is available
        audioEngine.prepare()
        
        // Set up audio input - get format after preparing
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Use a standard format if the input format is invalid
        let format: AVAudioFormat
        if recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 {
            format = recordingFormat
        } else {
            // Fallback to a standard format
            format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false) ?? recordingFormat
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak recognitionRequest] buffer, _ in
            recognitionRequest?.append(buffer)
        }
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if let error = error {
                    if error.localizedDescription.contains("kAFAssistantErrorDomain") {
                        // Ignore cancellation errors
                        return
                    }
                    self.errorMessage = "Recognition error: \(error.localizedDescription)"
                    self.stopListening()
                    return
                }
                
                if let result = result {
                    self.recognizedText = result.bestTranscription.formattedString
                    
                    if result.isFinal {
                        self.stopListening()
                    }
                }
            }
        }
        
        // Start audio engine
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            errorMessage = "Audio engine failed to start: \(error.localizedDescription)"
            stopListening()
        }
    }
    
    @MainActor
    func stopListening() {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Ignore errors when stopping
        }
        
        isListening = false
    }
    
    deinit {
        // Clean up resources without MainActor isolation
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        audioEngine.stop()
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }
}

