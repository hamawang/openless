import Foundation

/// 凭据存储相关错误。
///
/// `unparseable` / `futureVersion` 都意味着**不要碰原文件**，让用户自己处理或上报。
public enum CredentialsError: Error, Sendable, Equatable {
    /// 文件存在但 JSON 解析失败。携带文件 URL，方便给用户显示具体路径。
    case unparseable(URL)

    /// 文件版本号超过当前代码支持的范围。携带读到的版本号。
    case futureVersion(Int)

    /// 通用 IO 错误（读 / 创建目录等）。携带可读描述。
    case ioError(String)

    /// 备份 v0 文件失败。携带备份目标 URL。
    case backupFailed(URL)

    /// 写入 v1 文件失败。携带目标 URL 和失败描述。
    case writeFailed(URL, String)
}
