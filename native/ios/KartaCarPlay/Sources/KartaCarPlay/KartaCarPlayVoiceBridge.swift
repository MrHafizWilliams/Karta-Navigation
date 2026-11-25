#if canImport(AVFoundation) && canImport(Speech)
import AVFoundation
import Foundation
import Speech

/// Manages CarPlay navigation audio ducking (`AVAudioSession`) and hands-free
/// voice hazard reporting capture bridged back into Karta's regional NLU parser
/// (English, Bahasa Melayu, Manglish, Singlish).
public final class KartaCarPlayVoiceBridge {
    private let stateStore: KartaCarPlayStateStore
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isListening = false

    public init(stateStore: KartaCarPlayStateStore = .shared) {
        self.stateStore = stateStore
    }

    /// Configures `AVAudioSession` so Karta navigation prompts & hazard confirmations
    /// cleanly duck Spotify / Apple Music / Podcasts on the vehicle audio bus.
    public func configureNavigationAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback,
            mode: .voicePrompt,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        )
        try? session.setActive(true, options: [])
    }

    /// Triggered by the CarPlay quick-tap Voice button; attempts on-device speech
    /// recognition and emits either the live transcript or a fallback trigger to Dart.
    public func triggerHandsFreeHazardCapture(localeTag: String = "en-MY") {
        if isListening {
            stopListening()
            return
        }

        stateStore.emitVoiceReportTriggered(localeTag: localeTag)

        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeTag)) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            return
        }

        startSpeechSession(recognizer: recognizer, localeTag: localeTag)
    }

    public func stopListening() {
        isListening = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        configureNavigationAudioSession()
    }

    private func startSpeechSession(recognizer: SFSpeechRecognizer, localeTag: String) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.duckOthers, .allowBluetooth, .defaultToSpeaker]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        if #available(iOS 13.0, *), recognizer.supportsOnDeviceRecognition {
            // Privacy-first: keep raw speech transcription strictly on-device when supported.
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request
        self.isListening = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stopListening()
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let finalResult = result, finalResult.isFinal {
                let text = finalResult.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    self.stateStore.emitVoiceTranscript(text, localeTag: localeTag)
                }
                self.stopListening()
            } else if error != nil {
                self.stopListening()
            }
        }
    }
}
#endif
