import AppKit
import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation
import OSLog

@MainActor
final class AudioRecorder {
    private let logger = WishperLog.voicePipeline
    nonisolated(unsafe) private var audioUnit: AudioUnit?
    nonisolated(unsafe) private var audioBuffer: [Float] = []
    nonisolated(unsafe) private var smoothedLevel: Float = 0
    nonisolated(unsafe) private var deviceSampleRate: Double = 16000
    private let lock = NSLock()
    private(set) var isRecording = false
    nonisolated let sampleRate: Double = 16000
    private let waveformFloor: Float = 0.06

    /// Check and request microphone permission once at startup
    static func checkMicPermission() async -> Bool {
        let logger = WishperLog.voicePipeline
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.debug("microphone authorization status=\(status.rawValue)")

        switch status {
        case .authorized:
            logger.debug("microphone permission already granted")
            return true
        case .notDetermined:
            logger.info("microphone permission requesting")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            logger.info("microphone permission \(granted ? "granted" : "denied", privacy: .public)")
            return granted
        case .denied, .restricted:
            // Try requesting anyway — sometimes status is wrong for new bundle IDs
            logger.info("microphone permission denied attempting retry")
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if granted {
                logger.info("microphone permission granted after retry")
                return true
            }
            logger.info("microphone permission denied opening system settings")
            // Open the settings pane so user can grant manually
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
            return false
        @unknown default:
            return false
        }
    }

    func start() throws {
        guard !isRecording else { return }

        lock.lock()
        audioBuffer = []
        smoothedLevel = 0
        lock.unlock()

        var createdAudioUnit: AudioUnit?

        do {
            let deviceID = try Self.defaultInputDeviceID()
            let deviceFormat = try Self.deviceStreamFormat(for: deviceID)
            let captureFormat = Self.captureFormat(for: deviceFormat)

            deviceSampleRate = captureFormat.mSampleRate

            createdAudioUnit = try Self.makeHALAudioUnit()
            guard let audioUnit = createdAudioUnit else {
                throw AudioRecorderError.audioComponentCreationFailed("missing audio unit instance", noErr)
            }

            var enableInput: UInt32 = 1
            try Self.checkStatus(
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_EnableIO,
                    kAudioUnitScope_Input,
                    1,
                    &enableInput,
                    UInt32(MemoryLayout<UInt32>.size)
                ),
                operation: "enable input on HAL bus 1"
            )

            var disableOutput: UInt32 = 0
            try Self.checkStatus(
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_EnableIO,
                    kAudioUnitScope_Output,
                    0,
                    &disableOutput,
                    UInt32(MemoryLayout<UInt32>.size)
                ),
                operation: "disable output on HAL bus 0"
            )

            var mutableDeviceID = deviceID
            try Self.checkStatus(
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &mutableDeviceID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                ),
                operation: "set current input device"
            )

            var mutableCaptureFormat = captureFormat
            try Self.checkStatus(
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioUnitProperty_StreamFormat,
                    kAudioUnitScope_Output,
                    1,
                    &mutableCaptureFormat,
                    UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                ),
                operation: "apply capture stream format on output scope bus 1"
            )

            var shouldAllocateBuffer: UInt32 = 1
            try Self.checkStatus(
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioUnitProperty_ShouldAllocateBuffer,
                    kAudioUnitScope_Output,
                    1,
                    &shouldAllocateBuffer,
                    UInt32(MemoryLayout<UInt32>.size)
                ),
                operation: "allow HAL input buffer allocation"
            )

            var callback = AURenderCallbackStruct(
                inputProc: Self.inputCallback,
                inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
            )
            try Self.checkStatus(
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_SetInputCallback,
                    kAudioUnitScope_Global,
                    0,
                    &callback,
                    UInt32(MemoryLayout<AURenderCallbackStruct>.size)
                ),
                operation: "install HAL input callback"
            )

            self.audioUnit = audioUnit

            try Self.checkStatus(AudioUnitInitialize(audioUnit), operation: "initialize HAL audio unit")
            try Self.checkStatus(AudioOutputUnitStart(audioUnit), operation: "start HAL audio unit")

            isRecording = true
            logger.info(
                "recorder started deviceSampleRate=\(self.deviceSampleRate, format: .fixed(precision: 0)) target=\(self.sampleRate, format: .fixed(precision: 0)) channels=\(captureFormat.mChannelsPerFrame)"
            )
        } catch {
            if let audioUnit = createdAudioUnit {
                AudioOutputUnitStop(audioUnit)
                AudioUnitUninitialize(audioUnit)
                AudioComponentInstanceDispose(audioUnit)
            }
            self.audioUnit = nil
            deviceSampleRate = sampleRate
            throw error
        }
    }

    func stop() {
        guard isRecording else { return }

        if let audioUnit {
            AudioOutputUnitStop(audioUnit)
            AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
            self.audioUnit = nil
        }

        isRecording = false

        lock.lock()
        smoothedLevel = 0
        lock.unlock()

        logger.info("recorder stopped samples=\(self.audioBuffer.count)")
    }

    func getAudio() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return audioBuffer
    }

    func getRecentAudio(seconds: Double = 0.5) -> [Float] {
        let audio = getAudio()
        let sampleCount = Int(seconds * sampleRate)
        if audio.count <= sampleCount { return audio }
        return Array(audio.suffix(sampleCount))
    }

    func isSilent(threshold: Float = -55) -> Bool {
        let audio = getAudio()
        guard !audio.isEmpty else { return true }

        let rms = sqrt(audio.map { $0 * $0 }.reduce(0, +) / Float(audio.count))
        guard rms > 0 else { return true }

        let rmsDB = 20 * log10(rms)
        return rmsDB < threshold
    }

    func currentNormalizedLevel() -> CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return CGFloat(max(0, min(smoothedLevel, 1)))
    }

    func currentWaveformLevels(barCount: Int = 11) -> [CGFloat] {
        guard barCount > 0 else { return [] }

        let recentAudio: [Float]
        lock.lock()
        let sampleCount = min(audioBuffer.count, Int(sampleRate * 0.35))
        recentAudio = sampleCount > 0 ? Array(audioBuffer.suffix(sampleCount)) : []
        lock.unlock()

        guard !recentAudio.isEmpty else {
            return Array(repeating: CGFloat(waveformFloor), count: barCount)
        }

        let bucketSize = max(1, recentAudio.count / barCount)
        let levels = stride(from: 0, to: recentAudio.count, by: bucketSize).map { startIndex -> CGFloat in
            let endIndex = min(startIndex + bucketSize, recentAudio.count)
            let bucket = Array(recentAudio[startIndex..<endIndex])
            let normalizedLevel = Self.normalizedLevel(for: bucket)
            return CGFloat(Self.displayLevel(for: normalizedLevel))
        }

        if levels.count >= barCount {
            return Array(levels.suffix(barCount))
        }

        let padding = Array(repeating: CGFloat(waveformFloor), count: barCount - levels.count)
        return padding + levels
    }

    var duration: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(audioBuffer.count) / sampleRate
    }

    static let inputCallback: AURenderCallback = { inRefCon, ioActionFlags, inTimeStamp, _, inNumberFrames, _ in
        let recorder = Unmanaged<AudioRecorder>.fromOpaque(inRefCon).takeUnretainedValue()
        return recorder.handleInput(
            ioActionFlags: ioActionFlags,
            inTimeStamp: inTimeStamp,
            inNumberFrames: inNumberFrames
        )
    }

    nonisolated private func handleInput(
        ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        inTimeStamp: UnsafePointer<AudioTimeStamp>,
        inNumberFrames: UInt32
    ) -> OSStatus {
        guard let audioUnit else { return noErr }

        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil)
        )

        let status = AudioUnitRender(audioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, &bufferList)
        guard status == noErr else { return status }

        let frameCount = Int(bufferList.mBuffers.mDataByteSize) / MemoryLayout<Float>.stride
        guard frameCount > 0 else { return noErr }

        let samples = Self.extractFloatSamples(from: bufferList.mBuffers, frameCount: frameCount)
        let resampledSamples = Self.resample(samples, from: deviceSampleRate, to: sampleRate)
        appendCapturedSamples(resampledSamples)
        return noErr
    }

    nonisolated private func appendCapturedSamples(_ samples: [Float]) {
        guard !samples.isEmpty else { return }

        let normalizedLevel = Self.normalizedLevel(for: samples)

        lock.lock()
        audioBuffer.append(contentsOf: samples)
        if normalizedLevel > smoothedLevel {
            smoothedLevel = (smoothedLevel * 0.65) + (normalizedLevel * 0.35)
        } else {
            smoothedLevel = (smoothedLevel * 0.86) + (normalizedLevel * 0.14)
        }
        lock.unlock()
    }

    private static func makeHALAudioUnit() throws -> AudioUnit {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioRecorderError.audioComponentNotFound
        }

        var audioUnit: AudioUnit?
        try checkStatus(
            AudioComponentInstanceNew(component, &audioUnit),
            operation: "create HAL audio unit"
        )

        guard let audioUnit else {
            throw AudioRecorderError.audioComponentCreationFailed("create HAL audio unit", noErr)
        }

        return audioUnit
    }

    private static func defaultInputDeviceID() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        try checkStatus(
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                &deviceID
            ),
            operation: "get default input device"
        )

        guard deviceID != 0 else {
            throw AudioRecorderError.defaultInputDeviceUnavailable
        }

        return deviceID
    }

    private static func deviceStreamFormat(for deviceID: AudioDeviceID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        try checkStatus(
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &format),
            operation: "get device stream format"
        )

        return format
    }

    private static func captureFormat(for deviceFormat: AudioStreamBasicDescription) -> AudioStreamBasicDescription {
        let sampleRate = deviceFormat.mSampleRate > 0 ? deviceFormat.mSampleRate : 16000

        return AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

    private static func checkStatus(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw AudioRecorderError.audioComponentCreationFailed(operation, status)
        }
    }

    nonisolated private static func extractFloatSamples(
        from buffer: AudioBuffer,
        frameCount: Int
    ) -> [Float] {
        guard
            frameCount > 0,
            let data = buffer.mData
        else {
            return []
        }

        let floatPointer = data.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: floatPointer, count: frameCount))
    }

    nonisolated private static func resample(
        _ samples: [Float],
        from sourceRate: Double,
        to targetRate: Double
    ) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard sourceRate > 0, targetRate > 0, sourceRate != targetRate else { return samples }

        let ratio = targetRate / sourceRate
        let outputCount = max(1, Int(Double(samples.count) * ratio))
        var output = [Float](repeating: 0, count: outputCount)

        for index in 0..<outputCount {
            let sourceIndex = Double(index) / ratio
            let sourceIndexInt = Int(sourceIndex)
            let fraction = Float(sourceIndex - Double(sourceIndexInt))

            if sourceIndexInt + 1 < samples.count {
                output[index] = samples[sourceIndexInt] * (1 - fraction) + samples[sourceIndexInt + 1] * fraction
            } else if sourceIndexInt < samples.count {
                output[index] = samples[sourceIndexInt]
            }
        }

        return output
    }

    nonisolated private static func normalizedLevel(for samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        guard rms > 0 else { return 0 }

        let rmsDB = 20 * log10(rms)
        let floorDB: Float = -52
        let ceilingDB: Float = -8
        let normalized = (rmsDB - floorDB) / (ceilingDB - floorDB)
        return max(0, min(normalized, 1))
    }

    nonisolated private static func displayLevel(for normalizedLevel: Float) -> Float {
        let clampedLevel = max(0, min(normalizedLevel, 1))
        let emphasizedLevel = pow(clampedLevel, 0.72)
        return max(0.08, min((emphasizedLevel * 0.92) + 0.08, 1))
    }

    enum AudioRecorderError: Error {
        case audioComponentNotFound
        case audioComponentCreationFailed(String, OSStatus)
        case defaultInputDeviceUnavailable
    }
}
