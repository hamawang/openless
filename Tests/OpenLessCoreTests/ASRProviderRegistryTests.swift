import XCTest
@testable import OpenLessCore

/// ASRProviderRegistry 的静态健康检查：当前应包含火山引擎 + Apple Speech +
/// 阿里 Paraformer + 自定义 Whisper 四条预设，id 不重复、displayName 非空、mode 合法。
///
/// 这些断言看起来很无聊，但 registry 直接被「配置」Tab 的 chip 列表与 vault 兜底逻辑用，
/// 漏一条都会变成"用户切不了 ASR / picker 空白"的运行期 bug。
final class ASRProviderRegistryTests: XCTestCase {

    func test_presets_haveExpectedCount() {
        // Arrange
        let presets = ASRProviderRegistry.presets

        // Act / Assert
        XCTAssertEqual(
            presets.count,
            4,
            "ASR 预设：volcengine / apple-speech / aliyun-paraformer / custom-openai-whisper"
        )
    }

    func test_presets_includeAllExpectedProviderIds() {
        // Arrange
        let expected: Set<String> = [
            "volcengine",
            "apple-speech",
            "aliyun-paraformer",
            "custom-openai-whisper",
        ]

        // Act
        let actualIds = Set(ASRProviderRegistry.presets.map(\.providerId))

        // Assert
        XCTAssertEqual(actualIds, expected)
    }

    func test_presets_haveUniqueProviderIds() {
        // Arrange
        let ids = ASRProviderRegistry.presets.map(\.providerId)

        // Act / Assert
        XCTAssertEqual(Set(ids).count, ids.count, "providerId 必须唯一，否则 vault 会被互相覆盖")
    }

    func test_presets_haveNonEmptyDisplayName() {
        for preset in ASRProviderRegistry.presets {
            XCTAssertFalse(preset.displayName.isEmpty, "preset \(preset.providerId) 的 displayName 不能为空")
        }
    }

    func test_presets_haveNonEmptyHelpText() {
        for preset in ASRProviderRegistry.presets {
            XCTAssertFalse(preset.helpText.isEmpty, "preset \(preset.providerId) 的 helpText 不能为空")
        }
    }

    func test_volcenginePreset_isStreaming() {
        // Arrange
        let preset = ASRProviderRegistry.preset(for: "volcengine")

        // Act / Assert
        XCTAssertNotNil(preset)
        XCTAssertEqual(preset?.mode, .streaming)
    }

    func test_appleSpeechPreset_isStreaming() {
        // Arrange
        let preset = ASRProviderRegistry.preset(for: "apple-speech")

        // Act / Assert
        XCTAssertNotNil(preset)
        XCTAssertEqual(preset?.mode, .streaming)
    }

    func test_aliyunParaformerPreset_isStreaming() {
        // Arrange
        let preset = ASRProviderRegistry.preset(for: "aliyun-paraformer")

        // Act / Assert
        XCTAssertNotNil(preset)
        XCTAssertEqual(preset?.mode, .streaming)
    }

    func test_customOpenAIWhisperPreset_isBatch() {
        // Arrange
        let preset = ASRProviderRegistry.preset(for: "custom-openai-whisper")

        // Act / Assert
        XCTAssertNotNil(preset)
        XCTAssertEqual(preset?.mode, .batch, "Whisper API 是批量上传形态")
    }

    func test_preset_lookup_returnsRegistered() {
        for preset in ASRProviderRegistry.presets {
            let resolved = ASRProviderRegistry.preset(for: preset.providerId)
            XCTAssertEqual(resolved, preset)
        }
    }

    func test_preset_lookup_unknownReturnsNil() {
        XCTAssertNil(ASRProviderRegistry.preset(for: "no-such-provider-xyz"))
    }
}
