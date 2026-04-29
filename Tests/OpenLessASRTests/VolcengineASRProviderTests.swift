import XCTest
@testable import OpenLessASR
import OpenLessCore

final class VolcengineASRProviderTests: XCTestCase {

    private func makeProvider() -> VolcengineASRProvider {
        let creds = VolcengineCredentials(
            appID: "test-app",
            accessToken: "test-token",
            resourceID: VolcengineCredentials.defaultResourceId
        )
        return VolcengineASRProvider(credentials: creds)
    }

    // MARK: - info 元数据

    func test_info_reports_volcengine_streaming_provider() {
        // Arrange
        let provider = makeProvider()

        // Act
        let info = provider.info

        // Assert
        XCTAssertEqual(info.providerId, "volcengine")
        XCTAssertEqual(info.mode, .streaming)
        XCTAssertTrue(info.supportsHotwords)
    }

    func test_info_displayName_is_localized_chinese() {
        // Arrange
        let provider = makeProvider()

        // Act
        let displayName = provider.info.displayName

        // Assert
        XCTAssertEqual(displayName, "火山引擎")
    }

    // MARK: - 批量入口在流式 provider 上必须明确不支持

    func test_transcribeBatch_throws_unsupportedMode() async {
        // Arrange
        let provider = makeProvider()
        let pcm = Data(repeating: 0, count: 32_000) // 1 秒静音

        // Act / Assert
        do {
            _ = try await provider.transcribeBatch(
                pcm: pcm,
                sampleRate: 16_000,
                channels: 1,
                language: "zh-CN",
                hotwords: []
            )
            XCTFail("transcribeBatch 应抛 ASRError.unsupportedMode")
        } catch let error as ASRError {
            XCTAssertEqual(error, .unsupportedMode)
        } catch {
            XCTFail("应抛 ASRError，实际抛: \(error)")
        }
    }
}

// MARK: - ASRProviderInfo / ASRError 基础形状

final class ASRProviderInfoTests: XCTestCase {

    func test_info_struct_is_value_equal() {
        // Arrange
        let a = ASRProviderInfo(
            providerId: "x",
            displayName: "X",
            mode: .streaming,
            supportsHotwords: true,
            supportsLanguageHint: true,
            supportsPartialResults: true
        )
        let b = ASRProviderInfo(
            providerId: "x",
            displayName: "X",
            mode: .streaming,
            supportsHotwords: true,
            supportsLanguageHint: true,
            supportsPartialResults: true
        )

        // Act / Assert
        XCTAssertEqual(a, b)
    }

    func test_asrError_unsupportedMode_is_equatable() {
        // Arrange
        let lhs: ASRError = .unsupportedMode
        let rhs: ASRError = .unsupportedMode

        // Act / Assert
        XCTAssertEqual(lhs, rhs)
        XCTAssertNotEqual(lhs, .missingCredentials)
        XCTAssertNotEqual(lhs, .timeout)
    }

    func test_asrMode_codable_roundtrips() throws {
        // Arrange
        let original: ASRMode = .batch

        // Act
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ASRMode.self, from: encoded)

        // Assert
        XCTAssertEqual(decoded, original)
    }
}
