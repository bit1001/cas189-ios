import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// 天翼云盘 PC 网页接口（/api/open/file/listFiles.action）返回的是 XML，
/// 不是 JSON —— 结构与 `<listFiles><fileList><count/><folder/>…<file/>…</fileList></listFiles>`。
/// 这里用 XMLParser 转成字段字典，再映射成 CloudEntry。
public enum WebListParser {

    public static func parse(_ data: Data) throws -> [CloudEntry] {
        let p = ListFilesDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = p
        guard parser.parse() else {
            throw CASError.api(code: "XML", message: "列表 XML 解析失败：\(parser.parserError?.localizedDescription ?? "unknown")")
        }
        var out: [CloudEntry] = []
        for f in p.folders {
            guard let id = f["id"], let name = f["name"], !id.isEmpty else { continue }
            out.append(CloudEntry(id: id, name: name, size: 0, isFolder: true,
                                  md5: nil, parentId: f["parentId"] ?? "-11"))
        }
        for f in p.files {
            guard let id = f["id"], let name = f["name"], !id.isEmpty else { continue }
            let size = Int64(f["size"] ?? "0") ?? 0
            out.append(CloudEntry(id: id, name: name, size: size, isFolder: false,
                                  md5: f["md5"], parentId: f["parentId"] ?? "-11",
                                  iconURL: f["smallUrl"]))
        }
        return out
    }

    public static func total(from data: Data) -> Int? {
        guard let text = String(data: data, encoding: .utf8),
              let r = text.range(of: "<count>"),
              let end = text.range(of: "</count>", range: r.upperBound..<text.endIndex)
        else { return nil }
        return Int(text[r.upperBound..<end.lowerBound])
    }

    private final class ListFilesDelegate: NSObject, XMLParserDelegate {
        var folders: [[String: String]] = []
        var files: [[String: String]] = []
        private var current: [String: String] = [:]
        private var text = ""
        private var inItem = false
        private var itemTag = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            text = ""
            if elementName == "file" || elementName == "folder" {
                inItem = true
                itemTag = elementName
                current = [:]
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inItem { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String,
                    namespaceURI: String?, qualifiedName: String?) {
            if inItem && elementName == itemTag {
                if itemTag == "folder" { folders.append(current) } else { files.append(current) }
                inItem = false
                current = [:]
            } else if inItem {
                current[elementName] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            text = ""
        }
    }
}
