import Foundation

/// 环境自检。LiveContainer 这类宿主环境会改 HOME / TMPDIR，
/// 而文件选择器的不同工作模式在不同环境下行为差异很大，
/// 必须先看清进程到底运行在什么样的目录结构里。
enum Diagnostics {

    static func lines() -> [String] {
        var out: [String] = []
        let env = ProcessInfo.processInfo.environment
        out.append("Bundle: \(Bundle.main.bundleIdentifier ?? "-")")
        out.append("HOME: \(env["HOME"] ?? "<未设置>")")
        out.append("TMPDIR: \(env["TMPDIR"] ?? "<未设置>")")

        let tmp = FileManager.default.temporaryDirectory.path
        out.append("temporaryDirectory: \(tmp)")
        let isLink = (try? FileManager.default.destinationOfSymbolicLink(atPath: tmp)) != nil
        out.append(isLink
            ? "TMPDIR 是 symlink（导入模式复制会静默失败）"
            : "TMPDIR 不是 symlink")

        let probe = FileManager.default.temporaryDirectory
            .appendingPathComponent(".probe-189cas")
        let writable = (try? Data("x".utf8).write(to: probe)) != nil
        out.append("TMPDIR 可写: \(writable ? "是" : "否")")
        try? FileManager.default.removeItem(at: probe)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        out.append("Documents: \(docs)")
        out.append("Documents 可写: \(FileManager.default.isWritableFile(atPath: docs) ? "是" : "否")")
        return out
    }
}
