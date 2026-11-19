import Foundation

/// The overview's strings, as design v0.2 writes them.
public enum OverviewCopy {
    public static func subtitle(links: Int, mode: AggregationMode?, server: String?) -> String { "" }
    public static func linkDetail(enabled: Bool, standby: Bool, rate: Int64) -> String { "" }
    public static func exitDetail(direct: Bool, mode: AggregationMode?, rate: Int64) -> String { "" }
    public static func exitName(node: String, server: String?, mode: AggregationMode?) -> String { "" }
    public static func centre(mode: AggregationMode?, rate: Int64) -> String { "" }
}
