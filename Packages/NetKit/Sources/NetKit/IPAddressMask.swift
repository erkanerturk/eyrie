/// Hides every group of an address but the last — enough to tell networks
/// apart at a glance, not enough to read the address off a shared screen.
/// Separators survive, so the masked string keeps the original's width.
enum IPAddressMask {
    static func mask(_ address: String) -> String {
        guard let cut = address.lastIndex(where: { $0 == "." || $0 == ":" }) else {
            return address
        }
        let head = address[..<cut].map { $0 == "." || $0 == ":" ? $0 : "•" }
        return String(head) + address[cut...]
    }
}
