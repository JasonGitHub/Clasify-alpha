import SwiftUI

/// Card CG (CLA-166, changes 381-385): Help › Report a Problem. A small window in the device's
/// style: the device title bar, the LCD gradient, the selected-row blue. It shows words and a
/// text box, and hands the report to `onSend`; the app sends it. Then the Thanks screen with
/// the About capybara's wave, also with no connection (the app keeps the report in memory).
public struct ReportProblem: View {
    public static let title = "Report a Problem"
    public static let width: CGFloat = 380
    static let formHeight: CGFloat = 262, thanksHeight: CGFloat = 246
    static let hint = "A song didn’t play, the wheel got stuck…"

    let onSend: (_ text: String, _ writeBack: Bool) -> Void
    let onClose: () -> Void
    /// Snapshot tests: the text, the Thanks screen and the wave's time.
    let fixedTime: Double?

    @State private var text: String
    @State private var writeBack = true
    @State private var sent: Bool
    @State private var sentAt = Date.distantFuture
    @State private var waveDone = false
    @FocusState private var typing: Bool

    public init(onSend: @escaping (String, Bool) -> Void, onClose: @escaping () -> Void) {
        self.init(text: "", sent: false, fixedTime: nil, onSend: onSend, onClose: onClose)
    }

    init(text: String, sent: Bool, fixedTime: Double?, onSend: @escaping (String, Bool) -> Void = { _, _ in }, onClose: @escaping () -> Void = {}) {
        (self.onSend, self.onClose, self.fixedTime) = (onSend, onClose, fixedTime)
        _text = State(initialValue: text)
        _sent = State(initialValue: sent)
    }

    /// An empty box cannot be sent (384).
    var report: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var body: some View {
        VStack(spacing: 0) {
            titleBar
            if sent { thanks } else { form }
        }
        .frame(width: Self.width, height: sent ? Self.thanksHeight : Self.formHeight, alignment: .top)
        .background(LinearGradient(colors: [Color(hex: 0xf4f8fb), Color(hex: 0xd6e2ec)], startPoint: .top, endPoint: .bottom))
        .font(.helvetica(12))
    }

    /// The device title bar (.a-hdr): 26 pt. macOS draws the window buttons over its left end.
    private var titleBar: some View {
        Text(Self.title)
            .font(.helvetica(11.7, bold: true))
            .foregroundStyle(Color(hex: 0x1b1f24))
            .frame(maxWidth: .infinity)
            .frame(height: 25)
            .background(LinearGradient(colors: [.white, Color(hex: 0xc9d2db)], startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0x8f99a3)).frame(height: 1).offset(y: 1) }
            .padding(.bottom, 1)
    }

    /// 382, 383: the box, the write-back check box, Cancel and Send.
    private var form: some View {
        ZStack(alignment: .topLeading) {
            Text("What went wrong?")
                .font(.helvetica(11, bold: true))
                .foregroundStyle(Color(hex: 0x5d6772))
                .offset(x: 14, y: 12)
            box.frame(width: Self.width - 24, height: 104).offset(x: 12, y: 29)
            checkBox.offset(x: 14, y: 145)
            HStack(spacing: 6) {
                button("Cancel", filled: false, action: onClose).keyboardShortcut(.cancelAction)
                button("Send", filled: true, action: send)
                    .keyboardShortcut(.return, modifiers: .command)  // Return adds a line; ⌘Return sends
                    .disabled(report.isEmpty)
                    .opacity(report.isEmpty ? 0.45 : 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding([.trailing, .bottom], 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The white box with the blue focus ring and the grey hint; typing starts at once.
    private var box: some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        return ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(Self.hint).foregroundStyle(Color(hex: 0x8a949e)).padding(.horizontal, 5).allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .focused($typing)
                .foregroundStyle(Color(hex: 0x1b1f24))
                .tint(Color(hex: 0x1f6fd1))
        }
        .font(.helvetica(12.5))
        .lineSpacing(1.5)
        .padding(.vertical, 6).padding(.horizontal, 3)
        .background(shape.fill(.white))
        .overlay {
            shape.fill(LinearGradient(colors: [.black.opacity(0.12), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.03)))
                .allowsHitTesting(false)
        }
        .overlay { shape.strokeBorder(Color(hex: 0x5aa3f0), lineWidth: 1) }
        .background { shape.inset(by: -2).stroke(Color(hex: 0x5aa3f0, opacity: 0.35), lineWidth: 4) }
        .onAppear { typing = true }
    }

    /// 383: on by default; it only adds the account email.
    private var checkBox: some View {
        Button { writeBack.toggle() } label: {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(writeBack ? AnyShapeStyle(Self.blue) : AnyShapeStyle(Color.white))
                        .overlay { if !writeBack { RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0x8f99a3), lineWidth: 1) } }
                    if writeBack { Check().stroke(.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)).frame(width: 9, height: 8) }
                }
                .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Let us write back to you").font(.helvetica(12, bold: true)).foregroundStyle(Color(hex: 0x1b1f24))
                    Text("We’ll reply to your myPod account email.").font(.helvetica(10.5)).foregroundStyle(Color(hex: 0x5d6772))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(writeBack ? .isSelected : [])
    }

    /// 384: the About capybara on a soft white glow, the words and Done.
    private var thanks: some View {
        VStack(spacing: 0) {
            capybara.padding(.top, 14)
            Text("Got it, thank you!").font(.helvetica(15, bold: true)).foregroundStyle(Color(hex: 0x1b1f24)).padding(.top, 8)
            Text("Cappy reads every note.\nWe’ll look into it.")
                .font(.helvetica(11)).lineSpacing(3).multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: 0x5d6772)).padding(.top, 4)
            button("Done", filled: true, wide: true, action: onClose).keyboardShortcut(.defaultAction).padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    /// The About wave once (384): the stand pose 0.3 s, a cut to the wave rocking ±4° twice in
    /// 1.0 s (`PocketAbout.rock`), a cut back.
    private var capybara: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: fixedTime != nil || waveDone)) { context in
            let t = fixedTime ?? context.date.timeIntervalSince(sentAt)
            let waving = t >= 0.3 && t < 1.3
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.95), .white.opacity(0)], center: .center, startRadius: 0, endRadius: 66))
                    .frame(width: 132, height: 132)
                if let image = PocketAbout.poses[waving ? .wave : .stand] {
                    Image(nsImage: image).resizable().interpolation(.high)
                        .rotationEffect(.degrees(waving ? PocketAbout.rock(t - 0.3) : 0), anchor: UnitPoint(x: 0.5, y: 0.92))
                }
            }
            .frame(width: 96, height: 96)
        }
        .accessibilityElement()
        .accessibilityLabel("Capybara with headphones, waving")
        .task {
            // One wave, then the timeline stops.
            try? await Task.sleep(for: .seconds(1.4))
            waveDone = true
        }
    }

    private func send() {
        guard !report.isEmpty else { return }
        onSend(report, writeBack)
        sentAt = .now
        sent = true
    }

    static let blue = LinearGradient(colors: [Color(hex: 0x5aa3f0), Color(hex: 0x1f6fd1)], startPoint: .top, endPoint: .bottom)

    /// 24 pt, corner 6, bold 13: blue text, or white on the selected-row blue.
    private func button(_ title: String, filled: Bool, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.helvetica(13, bold: true))
                .foregroundStyle(filled ? Color.white : Color(hex: 0x1f6fd1))
                .padding(.horizontal, wide ? 22 : 14)
                .frame(height: 24)
                .background { if filled { RoundedRectangle(cornerRadius: 6).fill(Self.blue) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The check box's tick, as in the mock's 9 x 8 path.
struct Check: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 9
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 1 * k, y: rect.minY + 4.2 * k))
        p.addLine(to: CGPoint(x: rect.minX + 3.4 * k, y: rect.minY + 6.5 * k))
        p.addLine(to: CGPoint(x: rect.minX + 8 * k, y: rect.minY + 1.3 * k))
        return p
    }
}
