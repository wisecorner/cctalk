import AVFoundation
import CoreAudio
import Combine

/// Records audio from the microphone using AVAudioRecorder
class AudioRecorder: NSObject, ObservableObject {

    enum RecordingError: Error, LocalizedError {
        case recorderInitFailed(Error)
        case permissionDenied
        case recordingFailed

        var errorDescription: String? {
            switch self {
            case .recorderInitFailed(let error):
                return "Failed to initialize recorder: \(error.localizedDescription)"
            case .permissionDenied:
                return "Microphone permission denied"
            case .recordingFailed:
                return "Recording failed"
            }
        }
    }

    // MARK: - Properties

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    @Published private(set) var isRecording = false
    @Published private(set) var recordingDuration: TimeInterval = 0

    private var durationTimer: Timer?

    // MARK: - Permission

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func checkPermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    // MARK: - Device Sample Rate Detection

    /// Gets the sample rate of the current default input device
    private func getDefaultInputSampleRate() -> Double {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            print("AudioRecorder: Failed to get default input device, using 44100 Hz")
            return 44100.0
        }

        var sampleRate: Float64 = 0
        var srSize = UInt32(MemoryLayout<Float64>.size)
        var srAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let srStatus = AudioObjectGetPropertyData(deviceID, &srAddress, 0, nil, &srSize, &sampleRate)

        if srStatus == noErr && sampleRate > 0 {
            print("AudioRecorder: Detected input sample rate: \(sampleRate) Hz")
            return sampleRate
        }

        print("AudioRecorder: Failed to get sample rate, using 44100 Hz")
        return 44100.0
    }

    // MARK: - Recording

    /// Starts recording audio to a temporary file
    /// - Returns: URL of the recording file
    /// - Throws: RecordingError if recording cannot start
    func startRecording() throws -> URL {
        guard checkPermission() else {
            throw RecordingError.permissionDenied
        }

        // Get native sample rate of input device
        let sampleRate = getDefaultInputSampleRate()

        // Create temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "voice_prompt_\(Date().timeIntervalSince1970).wav"
        let fileURL = tempDir.appendingPathComponent(fileName)

        recordingURL = fileURL

        // Recording settings matching device sample rate
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.prepareToRecord()

            guard audioRecorder?.record() == true else {
                throw RecordingError.recordingFailed
            }

            isRecording = true
            recordingDuration = 0
            startDurationTimer()

            print("AudioRecorder: Started recording to \(fileURL.path) at \(sampleRate) Hz")
            return fileURL

        } catch {
            throw RecordingError.recorderInitFailed(error)
        }
    }

    /// Stops recording and returns the URL of the recorded file
    /// - Returns: URL of the recorded audio file, or nil if not recording
    func stopRecording() -> URL? {
        guard isRecording else { return nil }

        stopDurationTimer()

        audioRecorder?.stop()
        isRecording = false

        let url = recordingURL
        audioRecorder = nil
        recordingURL = nil

        print("AudioRecorder: Stopped recording. Duration: \(recordingDuration)s")
        return url
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.recordingDuration = self.audioRecorder?.currentTime ?? self.recordingDuration + 0.1
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: - Cleanup

    /// Deletes a temporary recording file
    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    deinit {
        if isRecording {
            _ = stopRecording()
        }
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("AudioRecorder: Recording finished unsuccessfully")
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("AudioRecorder: Encode error: \(error.localizedDescription)")
        }
    }
}
