import AVFoundation
import Foundation
import JTCopilotCore
import Speech

/// Apple Speech 流式中文识别，替代 Windows 版的 Vosk 本地引擎。
/// 结果只用于实时预览与快速写入，最终文本仍由智谱 GLM-ASR + GLM-4.6 校正。
/// 所有方法均应在主线程调用；内部回调也统一派发到主线程。
final class AppleSpeechRecognizer {
    var onTranscript: ((LiveTranscriptUpdate) -> Void)?
    var onFailure: ((String) -> Void)?
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastHypothesis = ""
    private var active = false
    private var emittedFinal = false
    private var generation = 0
    private var consecutiveFailures = 0
    private var restartWorkItem: DispatchWorkItem?
    private var contextualStrings: [String] = []
    private var useOnDevice = false

    private(set) var isAvailable = false
    private(set) var isRunning = false

    init() {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    }

    func initialize() async -> Bool {
        guard let recognizer else {
            isAvailable = false
            return false
        }

        let granted = await Permissions.requestSpeech()
        guard granted else {
            isAvailable = false
            return false
        }

        useOnDevice = recognizer.supportsOnDeviceRecognition
        isAvailable = true
        return true
    }

    func setContextualStrings(_ words: [String]) {
        contextualStrings = Array(words.prefix(100))
    }

    @discardableResult
    func startSession() -> Bool {
        guard isAvailable,
              let recognizer,
              recognizer.isAvailable || recognizer.supportsOnDeviceRecognition else {
            return false
        }

        active = true
        consecutiveFailures = 0
        lastHypothesis = ""
        startRequest()
        return true
    }

    func append(pcm16: Data) {
        guard active, let request else { return }

        let frameCount = pcm16.count / MemoryLayout<Int16>.size
        guard frameCount > 0,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: AudioCaptureService.sampleRate,
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(frameCount)
              ),
              let channel = buffer.floatChannelData?[0] else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        pcm16.withUnsafeBytes { raw in
            for index in 0..<frameCount {
                let bits = raw.load(fromByteOffset: index * 2, as: UInt16.self)
                let sample = Int16(bitPattern: UInt16(littleEndian: bits))
                channel[index] = Float(sample) / 32_768.0
            }
        }

        request.append(buffer)
    }

    /// 结束会话并返回尚未提交的最后一段假设文本。
    func endSession() -> String {
        let finalText = lastHypothesis
        active = false
        isRunning = false
        generation += 1
        restartWorkItem?.cancel()
        restartWorkItem = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        lastHypothesis = ""
        emittedFinal = true
        return finalText
    }

    private func startRequest() {
        guard active, let recognizer else { return }

        generation += 1
        let currentGeneration = generation

        task?.cancel()
        request?.endAudio()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = contextualStrings

        if useOnDevice, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        self.request = request
        lastHypothesis = ""
        emittedFinal = false
        isRunning = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handle(generation: currentGeneration, result: result, error: error)
            }
        }
    }

    private func handle(
        generation currentGeneration: Int,
        result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        guard active, currentGeneration == generation else { return }

        if let result {
            let text = TranscriptMerger.normalizeSpeechText(result.bestTranscription.formattedString)

            if !text.isEmpty {
                lastHypothesis = text
                consecutiveFailures = 0
                if !result.isFinal {
                    onTranscript?(LiveTranscriptUpdate(text: text, isFinal: false))
                }
            }

            if result.isFinal {
                finishCurrentRequest(finalText: text)
                return
            }
        }

        guard let error else { return }

        // 请求达到系统时长上限或网络抖动时，先提交已有假设再无缝续接。
        if useOnDevice {
            useOnDevice = false
            finishCurrentRequest(finalText: lastHypothesis, scheduleRestart: true)
            return
        }

        consecutiveFailures += 1
        if consecutiveFailures >= 3 {
            finishCurrentRequest(finalText: lastHypothesis, scheduleRestart: false)
            active = false
            isRunning = false
            task = nil
            request = nil
            onFailure?("实时识别已停止：\(error.localizedDescription)")
            return
        }

        finishCurrentRequest(finalText: lastHypothesis, scheduleRestart: true)
    }

    private func finishCurrentRequest(finalText: String, scheduleRestart: Bool = true) {
        let text = TranscriptMerger.normalizeSpeechText(finalText)

        if !text.isEmpty, !emittedFinal {
            emittedFinal = true
            onTranscript?(LiveTranscriptUpdate(text: text, isFinal: true))
        }

        task = nil
        request = nil
        lastHypothesis = ""

        guard active, scheduleRestart else { return }
        generation += 1

        restartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.startRequest()
        }
        restartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
    }
}
