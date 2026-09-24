#!/usr/bin/env python3
"""Apply Loupe Controller UI redesign v3.11.2.

This script intentionally edits only the SwiftUI shell in
apps/LoupeControllerApp/LoupeControllerApp/LoupeControllerApp.swift.
It does not touch WebRTC, signaling, SDP/ICE/TURN, pairing payloads,
DTLS pinning, or reconnect logic.

Why a script instead of a broad blind replacement:
- The controller file is large and contains transport-critical wiring.
- The redesign should be reproducible on the MacBook after pulling the branch.
- The script creates a timestamped backup before touching the file.
"""

from __future__ import annotations

import datetime as _dt
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
APP_FILE = ROOT / "apps" / "LoupeControllerApp" / "LoupeControllerApp" / "LoupeControllerApp.swift"

NEW_WELCOME_BLOCK = r'''private enum LoupeTheme {
    static let ink = Color(red: 0.06, green: 0.07, blue: 0.12)
    static let violet = Color(red: 0.37, green: 0.22, blue: 0.92)
    static let blue = Color(red: 0.14, green: 0.42, blue: 0.98)
    static let cyan = Color(red: 0.10, green: 0.72, blue: 0.92)
    static let mint = Color(red: 0.15, green: 0.82, blue: 0.60)

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [violet, blue, cyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var screenBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.045, green: 0.050, blue: 0.080),
                Color(red: 0.075, green: 0.080, blue: 0.135),
                Color(red: 0.020, green: 0.025, blue: 0.045),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct WelcomeFlow: View {
    let onScanQR: () -> Void
    let onPaste: () -> Void
    let onFileImport: () -> Void
    let onShowAdvanced: () -> Void

    @State private var step: OnboardingStep = {
        if let raw = UserDefaults.standard.string(forKey: "loupe.debug.startStep"),
           let value = Int(raw), let s = OnboardingStep(rawValue: value) {
            return s
        }
        return .welcome
    }()
    @State private var pulse = false

    var body: some View {
        ZStack {
            LoupeTheme.screenBackground
                .ignoresSafeArea()

            Circle()
                .fill(LoupeTheme.violet.opacity(0.30))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: -180, y: -320)
                .allowsHitTesting(false)

            Circle()
                .fill(LoupeTheme.cyan.opacity(0.22))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: 180, y: 260)
                .allowsHitTesting(false)

            VStack(spacing: 22) {
                Spacer(minLength: 20)

                LoupeHeroLogo()
                    .padding(.bottom, 2)

                GlassCard {
                    VStack(spacing: 18) {
                        StepBadge(step: step)
                        stepContent
                            .id(step)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                    .frame(maxWidth: 520)
                }
                .padding(.horizontal, 22)

                stepIndicator

                if step == .pair {
                    quickActions
                        .padding(.horizontal, 22)
                } else {
                    primaryAction
                        .padding(.horizontal, 22)
                }

                Button(action: onShowAdvanced) {
                    Text("Pairing token manuell eingeben")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.70))
                }
                .padding(.top, 2)

                Spacer(minLength: 18)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            VStack(spacing: 12) {
                Text("Remote control for your Mac")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)

                Text("Private, fast and account-free. Pair once, then control your Mac from iPhone or iPad.")
                    .font(.callout)
                    .lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                HStack(spacing: 8) {
                    TrustBadge(title: "No account", systemImage: "person.crop.circle.badge.xmark")
                    TrustBadge(title: "No media cloud", systemImage: "icloud.slash")
                    TrustBadge(title: "Encrypted", systemImage: "lock.shield")
                }
                .padding(.top, 4)
            }

        case .connect:
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(.white.opacity(0.09))
                        .frame(width: 188, height: 188)
                        .overlay(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .stroke(.white.opacity(0.14), lineWidth: 1)
                        )

                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 88, weight: .light))
                        .foregroundStyle(.white)
                        .scaleEffect(pulse ? 1.05 : 0.98)
                        .shadow(color: LoupeTheme.cyan.opacity(0.55), radius: 22, x: 0, y: 8)
                }

                Text("Open LoupeHost on your Mac")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text("The host prints and saves a QR code. Scan it here to start the secure WebRTC session.")
                    .font(.callout)
                    .lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.70))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }

        case .pair:
            VStack(spacing: 12) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 66, weight: .regular))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, LoupeTheme.mint)
                    .shadow(color: LoupeTheme.mint.opacity(0.45), radius: 18, x: 0, y: 8)

                Text("Connect to your Mac")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Text("Use QR for the normal flow. Paste token and file import are fallback options for Mac or debugging.")
                    .font(.callout)
                    .lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.70))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(item == step ? .white : .white.opacity(0.22))
                    .frame(width: item == step ? 28 : 8, height: 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.82), value: step)
            }
        }
    }

    private var primaryAction: some View {
        Button {
            advance()
        } label: {
            HStack(spacing: 10) {
                Text(step == .connect ? "Continue" : "Start")
                    .font(.headline.weight(.semibold))
                Image(systemName: "arrow.right")
                    .font(.headline.weight(.semibold))
            }
            .frame(maxWidth: 520, minHeight: 56)
            .background(LoupeTheme.heroGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(.white)
            .shadow(color: LoupeTheme.blue.opacity(0.35), radius: 18, x: 0, y: 10)
        }
    }

    private var quickActions: some View {
        VStack(spacing: 12) {
            BigActionButton(
                title: "Scan QR code",
                systemImage: "qrcode.viewfinder",
                primary: true,
                disabled: !AppPlatform.supportsCameraPairing,
                action: onScanQR
            )

            HStack(spacing: 12) {
                BigActionButton(title: "Paste token", systemImage: "doc.on.clipboard", primary: false, disabled: false, action: onPaste)
                BigActionButton(title: "Open file", systemImage: "folder", primary: false, disabled: false, action: onFileImport)
            }
            .frame(maxWidth: 520)
        }
    }

    private func advance() {
        withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
            if let next = OnboardingStep(rawValue: step.rawValue + 1) {
                step = next
            }
        }
    }
}

private struct LoupeHeroLogo: View {
    @State private var glow = false

    var body: some View {
        ZStack {
            Circle()
                .fill(LoupeTheme.heroGradient)
                .frame(width: 118, height: 118)
                .blur(radius: glow ? 16 : 9)
                .opacity(0.62)

            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 118, height: 118)
                .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))

            Image(systemName: "viewfinder.circle.fill")
                .font(.system(size: 66, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, LoupeTheme.cyan)
        }
        .shadow(color: LoupeTheme.blue.opacity(0.35), radius: 28, x: 0, y: 16)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                glow.toggle()
            }
        }
        .accessibilityHidden(true)
    }
}

private struct BigActionButton: View {
    let title: String
    let systemImage: String
    let primary: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 12)
            .background(
                Group {
                    if primary {
                        LoupeTheme.heroGradient
                    } else {
                        LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom)
                    }
                },
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(primary ? 0.0 : 0.16), lineWidth: 1)
            )
            .foregroundStyle(.white)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
    }
}

private struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 18)
    }
}

private struct StepBadge: View {
    let step: OnboardingStep

    var body: some View {
        Text(step.title.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.white.opacity(0.10), in: Capsule())
    }
}

private struct TrustBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(.white.opacity(0.08), in: Capsule())
    }
}
'''

NEW_CONNECTION_FORM = r'''    private var connectionForm: some View {
        ZStack {
            LoupeTheme.screenBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(LoupeTheme.heroGradient)
                                        .frame(width: 58, height: 58)
                                    Image(systemName: "display.and.arrow.down")
                                        .font(.title2.weight(.semibold))
                                        .foregroundStyle(.white)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Connect to Mac")
                                        .font(.title2.weight(.bold))
                                        .foregroundStyle(.white)
                                    Text("Scan the QR code from LoupeHost or paste a pairing token.")
                                        .font(.callout)
                                        .foregroundStyle(.white.opacity(0.68))
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 0)
                            }

                            HStack(spacing: 8) {
                                TrustBadge(title: AppPlatform.deviceLabel, systemImage: "iphone")
                                TrustBadge(title: "Private session", systemImage: "lock.shield")
                                TrustBadge(title: "WebRTC", systemImage: "bolt.horizontal")
                            }
                        }
                    }

                    GlassCard {
                        VStack(spacing: 12) {
                            BigActionButton(
                                title: AppPlatform.supportsCameraPairing ? "Scan QR code" : "QR only on iPhone/iPad",
                                systemImage: "qrcode.viewfinder",
                                primary: true,
                                disabled: !AppPlatform.supportsCameraPairing,
                                action: { activeSheet = .scanner }
                            )

                            HStack(spacing: 12) {
                                BigActionButton(title: "Paste", systemImage: "doc.on.clipboard", primary: false, disabled: false) {
                                    pasteTokenFromClipboard()
                                }
                                BigActionButton(title: "Open file", systemImage: "folder", primary: false, disabled: false) {
                                    isTokenImporterPresented = true
                                }
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Pairing token")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)

                            TextEditor(text: $pairingToken)
                                .font(.system(.footnote, design: .monospaced))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .scrollContentBackground(.hidden)
                                .foregroundStyle(.white)
                                .frame(minHeight: 118)
                                .padding(10)
                                .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(.white.opacity(0.12), lineWidth: 1)
                                )

                            Button {
                                connectFromToken()
                            } label: {
                                Label("Connect", systemImage: "bolt.horizontal.circle.fill")
                                    .font(.headline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .background(LoupeTheme.heroGradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .foregroundStyle(.white)
                            .disabled(pairingToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .opacity(pairingToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                        }
                    }

                    if AppPlatform.isMacRuntime {
                        GlassCard {
                            Label("On Mac, paste the token from the Host console. Camera scanning stays disabled by design.", systemImage: "macbook.and.iphone")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.76))
                        }
                    }

                    if let errorMessage {
                        ErrorCard(message: errorMessage)
                            .padding(.horizontal, 2)
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Setup")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("1. Start LoupeHost on the Mac\n2. Open the QR image\n3. Scan from iPhone or iPad\n4. Test video, touch, trackpad, scroll and keyboard")
                                .font(.callout)
                                .lineSpacing(3)
                                .foregroundStyle(.white.opacity(0.68))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(22)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
    }
'''


def replace_between(text: str, start: str, end: str, replacement: str) -> tuple[str, int]:
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end), re.DOTALL)
    new_text, count = pattern.subn(replacement + "\n\n" + end, text, count=1)
    return new_text, count


def main() -> int:
    if not APP_FILE.exists():
        print(f"ERROR: missing file: {APP_FILE}", file=sys.stderr)
        return 2

    original = APP_FILE.read_text(encoding="utf-8")
    text = original

    text, welcome_count = replace_between(
        text,
        "private struct WelcomeFlow: View {",
        "@MainActor\nprivate struct PairingEntryView: View",
        NEW_WELCOME_BLOCK,
    )

    text, form_count = replace_between(
        text,
        "    private var connectionForm: some View {",
        "    @ViewBuilder\n    private func sheetContent(_ sheet: ActiveSheet) -> some View",
        NEW_CONNECTION_FORM,
    )

    if welcome_count != 1 or form_count != 1:
        print("ERROR: could not apply redesign safely", file=sys.stderr)
        print(f"welcome replacements={welcome_count}, form replacements={form_count}", file=sys.stderr)
        return 3

    if "display.value(forKey:" in text:
        print("ERROR: unsafe SCDisplay KVC still present in controller file unexpectedly", file=sys.stderr)
        return 4

    if text == original:
        print("No changes needed.")
        return 0

    stamp = _dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = APP_FILE.with_suffix(f".swift.backup-before-ui-redesign-{stamp}")
    backup.write_text(original, encoding="utf-8")
    APP_FILE.write_text(text, encoding="utf-8")

    print("Loupe Controller UI redesign v3.11.2 applied.")
    print(f"Backup: {backup}")
    print(f"Updated: {APP_FILE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
