import SwiftUI

struct TutorialOverlay: View {
    @Environment(\.colorScheme) private var scheme
    let engine: TutorialEngine

    var body: some View {
        if let step = engine.currentStep {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { }

                VStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: step.icon)
                                .font(.title2)
                                .foregroundStyle(AppTheme.accentGradient(for: scheme))
                                .frame(width: 40, height: 40)
                                .background(AppTheme.accent(for: scheme).opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .font(.headline)
                                HStack(spacing: 4) {
                                    Text("Step \(engine.progress.current) of \(engine.progress.total)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) { engine.skip() }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                                    .background(.quaternary, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }

                        Text(step.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        progressBar

                        HStack(spacing: 12) {
                            if engine.currentStepIndex > 0 {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) { engine.back() }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                            .font(.caption)
                                        Text("Back")
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer()

                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) { engine.next() }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(engine.currentStepIndex == engine.progress.total - 1 ? "Finish" : "Next")
                                    if engine.currentStepIndex < engine.progress.total - 1 {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.accent(for: scheme))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(AppTheme.accent(for: scheme).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(AppTheme.accent(for: scheme).opacity(0.4), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                    .background(AppTheme.cardBackground(for: scheme), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(AppTheme.accent(for: scheme).opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
                    .frame(maxWidth: 420)
                    .padding(32)

                    Spacer()
                }
            }
            .transition(.opacity)
            .onKeyPress(.rightArrow) {
                withAnimation(.easeInOut(duration: 0.25)) { engine.next() }
                return .handled
            }
            .onKeyPress(.leftArrow) {
                withAnimation(.easeInOut(duration: 0.25)) { engine.back() }
                return .handled
            }
            .onKeyPress(.escape) {
                withAnimation(.easeInOut(duration: 0.25)) { engine.skip() }
                return .handled
            }
            .onKeyPress(.return) {
                withAnimation(.easeInOut(duration: 0.25)) { engine.next() }
                return .handled
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.accent(for: scheme).opacity(0.12))
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppTheme.accentGradient(for: scheme))
                    .frame(width: geo.size.width * CGFloat(engine.progress.current) / CGFloat(engine.progress.total))
                    .animation(.easeInOut(duration: 0.3), value: engine.currentStepIndex)
            }
        }
        .frame(height: 4)
    }
}

struct TutorialOverlayModifier: ViewModifier {
    let engine: TutorialEngine

    func body(content: Content) -> some View {
        content.overlay {
            if engine.isActive {
                TutorialOverlay(engine: engine)
            }
        }
    }
}

extension View {
    func tutorialOverlay(_ engine: TutorialEngine) -> some View {
        modifier(TutorialOverlayModifier(engine: engine))
    }
}
