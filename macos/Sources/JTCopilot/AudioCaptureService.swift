import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
import JTCopilotCore

/// 16 kHz / 16-bit / mono 录音，写入 WAV，并向会话层提供 PCM 分片与音量。
final class AudioCaptureService {
    static let sampleRate: Double = 16_000
    static let bitsPerSample = 16
    static let channels = 1

    var onLevel: ((Double) -> Void)?
    var onPcm: ((Data, Double) -> Void)?

    private let stateLock = NSLock()
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var fileHandle: FileHandle?
    private var recordingURL: URL?
    private var startedAt: Date?
    private var cancelling = false
    private var bytesWritten: UInt32 = 0

    private(set) var isCapturing = false

    // MARK: - Devices

    func inputDevices() -> [AudioDeviceDescriptor] {
        let defaultID = defaultInputDeviceID()

        return audioDeviceIDs()
            .filter { hasInputStreams($0) }
            .map { deviceID in
                AudioDeviceDescriptor(
                    id: deviceUID(deviceID) ?? String(deviceID),
                    displayName: deviceName(deviceID) ?? "麦克风 \(deviceID)",
                    isDefault: deviceID == defaultID
                )
            }
    }

    // MARK: - Capture

    func start(deviceID deviceUID: String?) throws {
        guard !isCapturing else { return }

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw NSError(domain: "JTCopilot.Audio", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "未获得麦克风权限。请在系统设置 → 隐私与安全性 → 麦克风中允许 JT Copilot。"
            ])
        }

        AppPaths.ensureRecordingsDirectory()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        if let deviceUID, !deviceUID.isEmpty,
           let deviceID = audioDeviceID(forUID: deviceUID),
           let audioUnit = inputNode.audioUnit {
            var identifier = deviceID
            AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &identifier,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "JTCopilot.Audio", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "未检测到可用的麦克风。"
            ])
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: AudioCaptureService.sampleRate,
            channels: 1,
            interleaved: true
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(domain: "JTCopilot.Audio", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "无法初始化音频格式转换。"
            ])
        }

        let url = AppPaths.recordingsDirectory.appendingPathComponent(
            "recording-\(AudioCaptureService.timestamp())-\(UUID().uuidString).wav"
        )
        guard FileManager.default.createFile(atPath: url.path, contents: Data(repeating: 0, count: 44)),
              let handle = try? FileHandle(forWritingTo: url) else {
            throw NSError(domain: "JTCopilot.Audio", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "无法创建录音文件。"
            ])
        }
        _ = try? handle.seekToEnd()

        self.engine = engine
        self.converter = converter
        self.fileHandle = handle
        self.recordingURL = url
        self.startedAt = Date()
        self.bytesWritten = 0
        self.cancelling = false

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer: buffer, targetFormat: targetFormat)
        }

        engine.prepare()

        do {
            try engine.start()
            isCapturing = true
        } catch {
            inputNode.removeTap(onBus: 0)
            self.engine = nil
            self.converter = nil
            try? handle.close()
            self.fileHandle = nil
            self.recordingURL = nil
            try? FileManager.default.removeItem(at: url)
            throw NSError(domain: "JTCopilot.Audio", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "麦克风启动失败：\(error.localizedDescription)"
            ])
        }
    }

    func stop() -> AudioCaptureResult {
        guard isCapturing else {
            return AudioCaptureResult(recordingPath: nil, duration: 0)
        }

        isCapturing = false
        tearDownEngine()

        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0

        if cancelling {
            discardRecording()
            resetCaptureState()
            return AudioCaptureResult(recordingPath: nil, duration: duration)
        }

        let finalizedURL = finalizeRecording()
        resetCaptureState()
        return AudioCaptureResult(recordingPath: finalizedURL?.path, duration: duration)
    }

    func cancel() {
        guard engine != nil || isCapturing else { return }

        cancelling = true
        isCapturing = false
        tearDownEngine()
        discardRecording()
        resetCaptureState()
    }

    // MARK: - Audio tap

    private func handle(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        stateLock.lock()
        let converter = self.converter
        stateLock.unlock()

        guard let converter else { return }

        let ratio = AudioCaptureService.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return
        }

        var conversionError: NSError?
        var suppliedInput = false
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }

            suppliedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error,
              output.frameLength > 0,
              let samples = output.int16ChannelData?[0] else {
            return
        }

        let frameCount = Int(output.frameLength)
        let byteCount = frameCount * MemoryLayout<Int16>.size
        let data = Data(bytes: samples, count: byteCount)

        var peak = 0
        for index in 0..<frameCount {
            peak = max(peak, abs(Int(samples[index])))
        }

        let level = min(max(Double(peak) / 32_768.0 * 4.0, 0), 1)

        stateLock.lock()
        if let handle = fileHandle {
            try? handle.write(contentsOf: data)
            bytesWritten += UInt32(byteCount)
        }
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.onPcm?(data, level)
            self?.onLevel?(level)
        }
    }

    private func tearDownEngine() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    private func discardRecording() {
        stateLock.lock()
        try? fileHandle?.close()
        fileHandle = nil
        let url = recordingURL
        recordingURL = nil
        bytesWritten = 0
        stateLock.unlock()

        if let url {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func resetCaptureState() {
        engine = nil
        converter = nil
        startedAt = nil
        cancelling = false
    }

    private func finalizeRecording() -> URL? {
        guard let url = recordingURL else { return nil }

        stateLock.lock()
        let handle = fileHandle
        let byteCount = bytesWritten
        fileHandle = nil
        stateLock.unlock()

        if let handle {
            let header = AudioCaptureService.wavHeader(pcmByteCount: byteCount)
            try? handle.seek(toOffset: 0)
            try? handle.write(contentsOf: header)
            try? handle.close()
        }

        recordingURL = nil
        bytesWritten = 0
        return url
    }

    private static func wavHeader(pcmByteCount: UInt32) -> Data {
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLittleEndian(UInt32(36) + pcmByteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(16_000))
        data.appendLittleEndian(UInt32(32_000))
        data.appendLittleEndian(UInt16(2))
        data.appendLittleEndian(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        data.appendLittleEndian(pcmByteCount)
        return data
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    // MARK: - CoreAudio helpers

    private func audioDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size
        ) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var identifiers = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &identifiers
        ) == noErr else {
            return []
        }

        return identifiers
    }

    private func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return false
        }

        return size > 0
    }

    private func defaultInputDeviceID() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return deviceID
    }

    private func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        audioDeviceIDs().first { deviceUID($0) == uid }
    }

    private func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)

        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }

        guard status == noErr, let value else { return nil }
        return value as String
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)

        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }

        guard status == noErr, let value else { return nil }
        return value as String
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
