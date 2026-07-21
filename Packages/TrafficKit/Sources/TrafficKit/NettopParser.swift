import Foundation

/// Pure parser for `nettop -P -x -L 0 -J bytes_in,bytes_out` CSV output.
/// The header line repeats before every sample, so it doubles as the frame
/// delimiter. Process names are truncated and may contain dots, spaces or
/// commas — rows parse from the right: the last two fields are counters,
/// the digits after the final dot of the remainder are the pid.
public enum NettopParser {
    public static let headerLine = ",bytes_in,bytes_out,"

    public static func isValidHeader(_ line: String) -> Bool {
        line == headerLine
    }

    /// Rows of one frame (header excluded). Unparseable rows are skipped —
    /// one weird process name must not blank the whole card.
    public static func parseFrame(_ lines: [String]) -> [ProcessTraffic] {
        lines.compactMap(parseRow)
    }

    static func parseRow(_ line: String) -> ProcessTraffic? {
        var fields = line.split(separator: ",", omittingEmptySubsequences: false)
        // The trailing comma produces one empty final field.
        if fields.last == "" { fields.removeLast() }
        guard fields.count >= 3,
              let bytesOut = UInt64(fields.removeLast()),
              let bytesIn = UInt64(fields.removeLast())
        else { return nil }

        let nameAndPid = fields.joined(separator: ",")
        guard let dotIndex = nameAndPid.lastIndex(of: "."),
              let pid = Int32(nameAndPid[nameAndPid.index(after: dotIndex)...]),
              pid >= 0
        else { return nil }
        let name = String(nameAndPid[..<dotIndex])
        guard !name.isEmpty else { return nil }

        return ProcessTraffic(pid: pid, name: name, bytesIn: bytesIn, bytesOut: bytesOut)
    }
}
