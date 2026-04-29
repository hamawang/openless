import SwiftUI
import OpenLessCore
import OpenLessASR

@MainActor
struct LLMProviderChipRow: View {
    let presets: [LLMProviderRegistry.Preset]
    let selectedProviderId: String
    let activeProviderId: String
    let onSelect: (String) -> Void
    let onAddCustom: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.providerId) { preset in
                    ProviderChipButton(
                        title: preset.displayName,
                        symbol: chipSymbol(for: preset.providerId),
                        isSelected: selectedProviderId == preset.providerId,
                        isActive: activeProviderId == preset.providerId,
                        onSelect: { onSelect(preset.providerId) }
                    )
                }

                customProviderChip

                Button(action: onAddCustom) {
                    Label("自定义", systemImage: "plus.circle")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("添加自定义 OpenAI 兼容 LLM provider")
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var customProviderChip: some View {
        if !selectedProviderId.isEmpty,
           LLMProviderRegistry.preset(for: selectedProviderId) == nil {
            ProviderChipButton(
                title: "自定义 (\(selectedProviderId))",
                symbol: "slider.horizontal.3",
                isSelected: true,
                isActive: activeProviderId == selectedProviderId,
                onSelect: { onSelect(selectedProviderId) }
            )
        }
    }

    private func chipSymbol(for providerId: String) -> String {
        switch providerId {
        case "ark": return "sparkles"
        case "openai": return "circle.hexagongrid.fill"
        case "aliyun-dashscope": return "cloud.fill"
        case "deepseek": return "fish"
        case "moonshot": return "moon.stars"
        default: return "wand.and.stars"
        }
    }
}

@MainActor
struct ASRProviderChipRow: View {
    let presets: [ASRProviderRegistry.Preset]
    let selectedProviderId: String
    let activeProviderId: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.providerId) { preset in
                    ProviderChipButton(
                        title: preset.displayName,
                        symbol: chipSymbol(for: preset.providerId),
                        isSelected: selectedProviderId == preset.providerId,
                        isActive: activeProviderId == preset.providerId,
                        onSelect: { onSelect(preset.providerId) }
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chipSymbol(for providerId: String) -> String {
        switch providerId {
        case "volcengine": return "cloud.fill"
        case "apple-speech": return "applelogo"
        case "aliyun-paraformer": return "waveform.badge.mic"
        case "custom-openai-whisper": return "slider.horizontal.3"
        default: return "waveform"
        }
    }
}

@MainActor
private struct ProviderChipButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                if isActive {
                    Text("当前")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.green.opacity(0.18))
                        )
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.blue.opacity(0.6) : Color.primary.opacity(0.12), lineWidth: isSelected ? 1.5 : 1)
            )
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}
