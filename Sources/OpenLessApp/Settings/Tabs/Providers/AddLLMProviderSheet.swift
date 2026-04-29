import SwiftUI
import OpenLessCore

/// 添加 LLM provider 的 sheet：列出所有预设 + "自定义"；选 "自定义" 时多一步收集 slug + displayName。
@MainActor
struct AddLLMProviderSheet: View {
    @Binding var isPresented: Bool
    let existingIds: Set<String>
    let onAdd: (_ providerId: String, _ displayName: String) -> Void

    @State private var customId: String = ""
    @State private var customDisplayName: String = ""
    @State private var step: Step = .pick

    enum Step {
        case pick
        case customDetails
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(step == .pick ? "添加 LLM Provider" : "自定义 OpenAI 兼容 Provider")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                switch step {
                case .pick:
                    pickList
                case .customDetails:
                    customDetailsForm
                }
            }
            .frame(minHeight: 360, maxHeight: 480)
        }
        .frame(width: 520)
    }

    private var pickList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(LLMProviderRegistry.presets, id: \.providerId) { preset in
                presetRow(preset)
                Divider().padding(.leading, 16)
            }
            customRow
        }
        .padding(.vertical, 4)
    }

    private func presetRow(_ preset: LLMProviderRegistry.Preset) -> some View {
        let alreadyAdded = existingIds.contains(preset.providerId)
        return Button {
            guard !alreadyAdded else { return }
            onAdd(preset.providerId, preset.displayName)
            isPresented = false
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: alreadyAdded ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(alreadyAdded ? .green : .secondary)
                    .font(.system(size: 18))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(preset.defaultBaseURL.absoluteString)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(preset.helpText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(alreadyAdded)
        .help(alreadyAdded ? "已添加" : "添加 \(preset.displayName)")
    }

    private var customRow: some View {
        Button {
            step = .customDetails
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.blue)
                    .font(.system(size: 18))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LLMProviderRegistry.customDisplayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("任何遵循 OpenAI Chat Completions 协议的供应商都能填进来——比如自建网关、私有化部署、或表里没列的云厂商。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var customDetailsForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Provider ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("custom-gateway", text: $customId)
                    .textFieldStyle(.roundedBorder)
                Text("唯一 slug，建议小写字母 / 数字 / 短横线；不能与已存在的 id 重复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("展示名")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("公司内部网关", text: $customDisplayName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("返回") {
                    step = .pick
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("添加") {
                    let id = customId.trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                    onAdd(id, name)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isCustomReady)
            }
            .padding(.top, 6)
        }
        .padding(20)
    }

    private var isCustomReady: Bool {
        let id = customId.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !name.isEmpty else { return false }
        if LLMProviderRegistry.preset(for: id) != nil { return false }
        if existingIds.contains(id) { return false }
        return true
    }
}
