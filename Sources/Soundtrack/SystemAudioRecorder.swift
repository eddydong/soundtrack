import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum CaptureLog {
    static let url: URL = {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Soundtrack", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("soundtrack.log")
    }()

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let data = Data(line.utf8)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

enum CaptureSource: String, CaseIterable, Identifiable {
    case system
    case browser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Everything playing"
        case .browser: return "Browser only"
        }
    }

    var detail: String {
        switch self {
        case .system: return "Speakers, headphones, and every app"
        case .browser: return "Safari, Chrome, Arc, Brave, Edge, Firefox"
        }
    }
}

enum RecorderPhase: Equatable {
    case idle
    case recording
    case stopping
    case converting
    case failed(String)
}

@MainActor
final class SystemAudioRecorder: ObservableObject {
    @Published var source: CaptureSource = .system
    @Published private(set) var phase: RecorderPhase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var lastFile: URL?
    @Published private(set) var status: String =
        "Captures what your Mac plays. MP3s save to the Desktop. The microphone stays off."

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    var canToggle: Bool {
        switch phase {
        case .idle, .recording, .failed: return true
        case .stopping, .converting: return false
        }
    }

    private let engine = CaptureEngine()
    private let io = AudioFileWriter()
    private var wavURL: URL?
    private var startedAt: Date?
    private var tick: Timer?
    private let capturesDirectory: URL

    init() {
        capturesDirectory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        engine.onAudio = { [io] buffer in
            io.append(buffer)
        }
        engine.onMeter = { [weak self] value in
            Task { @MainActor in
                self?.level = value
            }
        }
        engine.onError = { [weak self] message in
            Task { @MainActor in
                self?.fail(message)
            }
        }
    }

    func runCommandLineIfNeeded() async {
        let args = CommandLine.arguments
        if args.contains("--browser") {
            source = .browser
        }
        guard let flag = args.firstIndex(of: "--seconds"),
              args.indices.contains(flag + 1),
              let seconds = TimeInterval(args[flag + 1]),
              seconds > 0 else {
            return
        }
        await start()
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        if isRecording {
            await stop()
        }
        if args.contains("--quit") {
            NSApp.terminate(nil)
        }
    }

    func toggle() {
        switch phase {
        case .recording:
            Task { await stop() }
        case .idle, .failed:
            Task { await start() }
        case .stopping, .converting:
            break
        }
    }

    func revealLastFile() {
        guard let lastFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastFile])
    }

    func openPrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for value in candidates {
            if let url = URL(string: value) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    private func start() async {
        lastFile = nil
        elapsed = 0
        level = 0
        phase = .idle
        status = "Starting system-audio capture…"
        CaptureLog.write("start argv=\(CommandLine.arguments) preflight=\(CGPreflightScreenCaptureAccess()) source=\(source.rawValue)")

        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }

        do {
            try FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
            let stamp = Self.filenameDate.string(from: Date())
            let wav = capturesDirectory.appendingPathComponent("soundtrack-\(stamp).wav")
            wavURL = wav
            io.reset(url: wav)
            try await engine.start(source: source)
            startedAt = Date()
            phase = .recording
            status = "Play the website. Stop when the music ends. MP3s land on your Desktop."
            CaptureLog.write("capture started \(wav.lastPathComponent)")
            startTick()
        } catch {
            CaptureLog.write("start failed: \(error)")
            fail(Self.describe(error))
        }
    }

    private func stop() async {
        guard isRecording else { return }
        phase = .stopping
        status = "Stopping capture…"
        tick?.invalidate()
        tick = nil
        await engine.stop()

        let snapshot = io.finish()
        let wav = wavURL
        wavURL = nil
        startedAt = nil
        level = 0

        if let error = snapshot.error {
            fail(error)
            return
        }

        guard let wav else {
            fail("Nothing was written.")
            return
        }

        guard snapshot.frames > 0 else {
            try? FileManager.default.removeItem(at: wav)
            fail("No system audio arrived. Play the site, then record again. If this is the first run, allow Soundtrack under System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen the app.")
            return
        }

        phase = .converting
        status = "Encoding MP3…"
        do {
            let mp3 = wav.deletingPathExtension().appendingPathExtension("mp3")
            try Self.encodeMP3(from: wav, to: mp3)
            try? FileManager.default.removeItem(at: wav)
            lastFile = mp3
            phase = .idle
            status = "Saved \(mp3.lastPathComponent) to your Desktop."
        } catch {
            fail(Self.describe(error))
        }
    }

    private func startTick() {
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
        RunLoop.main.add(tick!, forMode: .common)
    }

    private func fail(_ message: String) {
        tick?.invalidate()
        tick = nil
        Task { await engine.stop() }
        _ = io.finish()
        if let wavURL {
            try? FileManager.default.removeItem(at: wavURL)
        }
        wavURL = nil
        startedAt = nil
        level = 0
        phase = .failed(message)
        status = message
    }

    private static let filenameDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain {
            switch nsError.code {
            case SCStreamError.userDeclined.rawValue:
                return "macOS blocked capture. Allow Soundtrack in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen the app."
            case SCStreamError.failedToStartAudioCapture.rawValue:
                return "System-audio capture failed to start. Quit Soundtrack, toggle its permission off and on, then try again."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private static func encodeMP3(from wav: URL, to mp3: URL) throws {
        guard let lame = findLame() else {
            throw RecorderError.encoderMissing
        }
        let process = Process()
        process.executableURL = lame
        process.arguments = [
            "--silent",
            "-b", "320",
            "--noreplaygain",
            wav.path,
            mp3.path
        ]
        let stderr = Pipe()
        process.standardOutput = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "MP3 encoding failed"
            throw RecorderError.encoderFailed(text)
        }
    }

    private static func findLame() -> URL? {
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/lame", isDirectory: false)
        let candidates = [
            bundled,
            URL(fileURLWithPath: "/opt/homebrew/bin/lame"),
            URL(fileURLWithPath: "/usr/local/bin/lame")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

enum RecorderError: LocalizedError {
    case encoderMissing
    case encoderFailed(String)
    case noDisplay
    case noBrowser
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .encoderMissing:
            return "The bundled MP3 encoder is missing. Re-download Soundtrack and keep the app together as one file."
        case .encoderFailed(let text):
            return "Could not encode MP3. \(text)"
        case .noDisplay:
            return "No display was available to attach the system-audio tap."
        case .noBrowser:
            return "No browser is running. Open the site, then try again, or switch to Everything playing."
        case .writeFailed(let text):
            return text
        }
    }
}

final class AudioFileWriter: @unchecked Sendable {
    struct Snapshot {
        var frames: AVAudioFrameCount = 0
        var error: String?
    }

    private let lock = NSLock()
    private var file: AVAudioFile?
    private var url: URL?
    private var frames: AVAudioFrameCount = 0
    private var error: String?
    private var logged = false

    func reset(url: URL) {
        lock.lock()
        file = nil
        self.url = url
        frames = 0
        error = nil
        logged = false
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        do {
            let pcm = try Self.interleavedInt16(buffer)
            if !logged {
                logged = true
                CaptureLog.write("format in=\(Self.describe(buffer.format)) out=\(Self.describe(pcm.format))")
            }
            if file == nil {
                guard let url else { return }
                file = try AVAudioFile(
                    forWriting: url,
                    settings: pcm.format.settings,
                    commonFormat: .pcmFormatInt16,
                    interleaved: true
                )
            }
            guard let file else { return }
            try file.write(from: pcm)
            frames += pcm.frameLength
        } catch {
            self.error = error.localizedDescription
            CaptureLog.write("write failed: \(error.localizedDescription)")
        }
    }

    func finish() -> Snapshot {
        lock.lock()
        let snapshot = Snapshot(frames: frames, error: error)
        file = nil
        url = nil
        frames = 0
        error = nil
        lock.unlock()
        return snapshot
    }

    private static func interleavedInt16(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: buffer.format.sampleRate,
            channels: buffer.format.channelCount,
            interleaved: true
        ) else {
            throw RecorderError.writeFailed("Could not build a 16-bit WAV format.")
        }
        if buffer.format.commonFormat == .pcmFormatInt16, buffer.format.isInterleaved {
            return buffer
        }
        guard let converter = AVAudioConverter(from: buffer.format, to: format),
              let dest = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength) else {
            throw RecorderError.writeFailed("Could not convert system audio to WAV.")
        }
        var sent = false
        var nsError: NSError?
        let status = converter.convert(to: dest, error: &nsError) { _, outStatus in
            if sent {
                outStatus.pointee = .noDataNow
                return nil
            }
            sent = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let nsError { throw nsError }
        if status == .error {
            throw RecorderError.writeFailed("Audio conversion failed.")
        }
        return dest
    }

    private static func describe(_ format: AVAudioFormat) -> String {
        "\(Int(format.sampleRate))Hz \(format.channelCount)ch interleaved=\(format.isInterleaved)"
    }
}

final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onAudio: ((AVAudioPCMBuffer) -> Void)?
    var onMeter: ((Float) -> Void)?
    var onError: ((String) -> Void)?

    private let audioQueue = DispatchQueue(label: "com.eddy.soundtrack.audio")
    private let videoQueue = DispatchQueue(label: "com.eddy.soundtrack.video")
    private var stream: SCStream?
    private var lastMeterAt: CFAbsoluteTime = 0
    private var loggedBuffers = 0

    func start(source: CaptureSource) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw RecorderError.noDisplay
        }

        let filter: SCContentFilter
        switch source {
        case .system:
            filter = SCContentFilter(display: display, excludingWindows: [])
        case .browser:
            let browsers = content.applications.filter { Self.isBrowser($0.bundleIdentifier) }
            guard !browsers.isEmpty else { throw RecorderError.noBrowser }
            filter = SCContentFilter(display: display, including: browsers, exceptingWindows: [])
        }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false
        config.queueDepth = 3

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        try await stream.startCapture()
        self.stream = stream
        loggedBuffers = 0
        CaptureLog.write("SCStream started display=\(display.displayID)")
    }

    func stop() async {
        let current = stream
        stream = nil
        guard let current else { return }
        _ = await withTimeout(seconds: 3) {
            try? await current.stopCapture()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let buffer = Self.copyPCMBuffer(from: sampleBuffer) else { return }
        if loggedBuffers < 3, let asbd = sampleBuffer.formatDescription?.audioStreamBasicDescription {
            loggedBuffers += 1
            CaptureLog.write(
                "buffer[\(loggedBuffers)] samples=\(sampleBuffer.numSamples) rate=\(asbd.mSampleRate) ch=\(asbd.mChannelsPerFrame) rms=\(Self.rms(buffer))"
            )
        }
        onAudio?(buffer)
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastMeterAt > 0.06 {
            lastMeterAt = now
            onMeter?(Self.rms(buffer))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error.localizedDescription)
    }

    private static func isBrowser(_ bundleIdentifier: String) -> Bool {
        let id = bundleIdentifier.lowercased()
        let needles = [
            "com.apple.safari",
            "com.google.chrome",
            "com.brave.browser",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "company.thebrowser",
            "com.operasoftware.opera",
            "com.vivaldi",
            "com.kagi.orion",
            "com.apple.webkit.webcontent",
            "com.apple.webkit.gpu"
        ]
        return needles.contains { id.hasPrefix($0) || id.contains($0) }
    }

    private static func copyPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard var asbd = sampleBuffer.formatDescription?.audioStreamBasicDescription,
              let format = AVAudioFormat(streamDescription: &asbd) else {
            return nil
        }
        guard sampleBuffer.numSamples > 0 else { return nil }
        return try? sampleBuffer.withAudioBufferList { list, _ in
            guard let source = AVAudioPCMBuffer(
                pcmFormat: format,
                bufferListNoCopy: list.unsafePointer,
                deallocator: nil
            ) else {
                return nil
            }
            return copyOwned(source)
        }
    }

    private static func copyOwned(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else {
            return nil
        }
        copy.frameLength = source.frameLength
        let srcList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let destList = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard srcList.count == destList.count else { return nil }
        for index in 0..<srcList.count {
            let bytes = Int(srcList[index].mDataByteSize)
            destList[index].mDataByteSize = srcList[index].mDataByteSize
            if let src = srcList[index].mData, let dst = destList[index].mData, bytes > 0 {
                memcpy(dst, src, bytes)
            }
        }
        return copy
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return 0 }
        var sum: Float = 0
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for i in 0..<frames {
                let sample = samples[i]
                sum += sample * sample
            }
        }
        return min(1, sqrt(sum / Float(frames * channelCount)) * 4)
    }

    private func withTimeout<T>(seconds: TimeInterval, _ operation: @escaping () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? nil
        }
    }
}
