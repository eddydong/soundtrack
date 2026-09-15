import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var recorder: SystemAudioRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            sourcePicker
            meter
            controls
            footer
        }
        .padding(28)
        .frame(width: 420)
        .background(Palette.bg)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            AppLogo()
            VStack(alignment: .leading, spacing: 8) {
                Text("Soundtrack")
                    .font(.system(.largeTitle, design: .serif, weight: .medium))
                    .foregroundStyle(Palette.ink)
                Text("System playback → MP3")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Palette.muted)
                HStack(spacing: 8) {
                    Badge(text: "System route", symbol: "speaker.wave.2.fill")
                    Badge(text: "Mic off", symbol: "mic.slash.fill")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Capture")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.muted)
            ForEach(CaptureSource.allCases) { source in
                Button {
                    recorder.source = source
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: recorder.source == source ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(recorder.source == source ? Palette.red : Palette.muted)
                            .font(.body)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Text(source.detail)
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(recorder.source == source ? Palette.raised : Palette.well)
                    )
                }
                .buttonStyle(.plain)
                .disabled(recorder.isRecording)
            }
        }
    }

    private var meter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(timeString)
                    .font(.system(size: 28, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(recorder.isRecording ? "LIVE" : "Ready")
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(recorder.isRecording ? Palette.red : Palette.muted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.well)
                    Capsule()
                        .fill(meterGradient)
                        .frame(width: max(8, geo.size.width * CGFloat(recorder.level)))
                }
            }
            .frame(height: 10)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button(action: recorder.toggle) {
                HStack(spacing: 10) {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle.fill")
                    Text(buttonTitle)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(Palette.bg)
                .background(recorder.isRecording ? Palette.ink : Palette.red, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!recorder.canToggle)

            if recorder.lastFile != nil {
                Button("Show MP3 in Finder", action: recorder.revealLastFile)
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
            }

            if case .failed = recorder.phase {
                Button("Open Screen & System Audio settings", action: recorder.openPrivacySettings)
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.red)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var footer: some View {
        Text(recorder.status)
            .font(.callout)
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var buttonTitle: String {
        switch recorder.phase {
        case .recording: return "Stop"
        case .stopping: return "Stopping…"
        case .converting: return "Encoding MP3…"
        default: return "Record"
        }
    }

    private var timeString: String {
        let total = Int(recorder.elapsed)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var meterGradient: LinearGradient {
        LinearGradient(
            colors: [Palette.amber, Palette.red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct AppLogo: View {
    var body: some View {
        Group {
            if let image = NSImage(named: "AppIcon") ?? bundleLogo {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Palette.amber)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.well)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
    }

    private var bundleLogo: NSImage? {
        let names = ["AppIcon", "soundtrack-icon"]
        for name in names {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }
}

private struct Badge: View {
    let text: String
    let symbol: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(Palette.ink)
        .background(Palette.well, in: Capsule())
    }
}

private enum Palette {
    static let bg = Color(red: 0.09, green: 0.08, blue: 0.07)
    static let well = Color(red: 0.16, green: 0.14, blue: 0.12)
    static let raised = Color(red: 0.22, green: 0.14, blue: 0.12)
    static let ink = Color(red: 0.96, green: 0.93, blue: 0.88)
    static let muted = Color(red: 0.62, green: 0.57, blue: 0.52)
    static let red = Color(red: 0.86, green: 0.22, blue: 0.18)
    static let amber = Color(red: 0.93, green: 0.64, blue: 0.22)
}
