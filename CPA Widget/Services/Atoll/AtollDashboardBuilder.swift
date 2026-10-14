import AtollExtensionKit
import AppKit
import Foundation

struct AtollDashboardBuilder {
    struct Entry: Identifiable, Hashable {
        let selection: AtollSummarySelection
        let provider: String
        let account: String
        let window: String
        let fraction: Double?
        let resetText: String?
        var id: String { selection.id }
        var label: String { "\(provider) · \(account) · \(window)" }
    }

    struct Dashboard {
        let entries: [Entry]
        let pages: [AtollNotchExperienceDescriptor]
        let pageDwellSeconds: [Double]
        let summaryOptions: [Entry]
    }

    private static let bundleID = "vn.ppx.CPA-Widget"
    private static let blue = AtollColorDescriptor(red: 0.18, green: 0.48, blue: 0.94)

    func build(model: AppModel) -> Dashboard {
        build(providers: model.providers, lastUpdated: model.lastUpdated, errorMessage: model.errorMessage)
    }

    func build(providers: [ProviderSnapshot], lastUpdated: Date?, errorMessage: String?) -> Dashboard {
        let entries = flatten(providers)
        let stale = errorMessage != nil && lastUpdated != nil
        let status = lastUpdated == nil ? (errorMessage == nil ? "Awaiting connection" : "Connection error") : (entries.isEmpty ? "No enabled accounts" : "")
        let boundedEntries = entries.map(bound)
        let chunks = paginate(boundedEntries, status: status, stale: stale, updated: lastUpdated)
        let pages = chunks.enumerated().map { index, chunk in descriptor(html: htmlPage(entries: chunk, page: index + 1, total: chunks.count, status: status, stale: stale, updated: lastUpdated), page: index + 1, total: chunks.count, shortened: entries.contains(where: isShortened)) }
        let dwell = chunks.map(dwellSeconds)
        return Dashboard(entries: entries, pages: pages, pageDwellSeconds: dwell, summaryOptions: entries)
    }

    func summaryDescriptor(entry: Entry?, stale: Bool, updated: Date?) -> AtollLiveActivityDescriptor {
        let known = stale ? nil : entry?.fraction
        let color = known.map(colorFor) ?? .gray
        let label = entry.map { truncate($0.account, limit: 80) } ?? "No quota data"
        let detail: String
        if stale {
            let time = updated?.formatted(date: .abbreviated, time: .shortened) ?? "unknown"
            detail = truncate("Stale · Last success: \(time)", limit: 120)
        } else if let entry {
            detail = truncate("\(entry.window) · \(percentText(entry.fraction))", limit: 120)
        } else {
            detail = "Awaiting connection"
        }
        let indicator: AtollProgressIndicator? = known == nil ? nil : .ring(diameter: 26, strokeWidth: 3, color: color)
        let trailing: AtollTrailingContent = known == nil ? .text(stale ? "Stale" : "Unavailable", color: .gray) : .none
        return AtollLiveActivityDescriptor(
            id: "cpa-widget-summary", bundleIdentifier: Self.bundleID, priority: .normal,
            title: "CPA Widget", subtitle: truncate(label, limit: 80),
            leadingIcon: .symbol(name: "server.rack"), trailingContent: trailing,
            progressIndicator: indicator, progress: known ?? 0, accentColor: color,
            allowsMusicCoexistence: true, estimatedDuration: nil,
            sneakPeekConfig: .standard(duration: 2.5),
            sneakPeekTitle: truncate(entry?.provider ?? "CPA Widget", limit: 80),
            sneakPeekSubtitle: detail
        )
    }

    private func flatten(_ providers: [ProviderSnapshot]) -> [Entry] {
        var output: [Entry] = []
        for provider in providers {
            for account in provider.accounts {
                let name = account.credential.name.flatMap { $0.isEmpty ? nil : $0 } ?? account.credential.id
                let groups = account.quota?.groups ?? []
                var found = false
                for (groupIndex, group) in groups.enumerated() {
                    for (bucketIndex, bucket) in (group.buckets ?? []).enumerated() {
                        found = true
                        output.append(Entry(
                            selection: AtollSummarySelection(provider: provider.id, accountID: account.id, groupIndex: groupIndex, bucketIndex: bucketIndex),
                            provider: provider.id, account: name, window: bucket.window ?? group.displayName ?? "Quota",
                            fraction: bucket.availableFraction, resetText: resetText(bucket.resetTime)
                        ))
                    }
                }
                if !found {
                    output.append(Entry(selection: AtollSummarySelection(provider: provider.id, accountID: account.id, groupIndex: -1, bucketIndex: -1), provider: provider.id, account: name, window: "Quota unavailable", fraction: nil, resetText: nil))
                }
            }
        }
        return output
    }

    private func paginate(_ entries: [Entry], status: String, stale: Bool, updated: Date?) -> [[Entry]] {
        let initial: [[Entry]] = entries.isEmpty ? [[]] : stride(from: 0, to: entries.count, by: 4).map { start in
            Array(entries[start..<min(start + 4, entries.count)])
        }
        var result: [[Entry]] = []
        for page in initial {
            let html = htmlPage(entries: page, page: 1, total: 1, status: status, stale: stale, updated: updated)
            if html.utf8.count <= 20_000 || page.count <= 1 {
                result.append(page)
            } else {
                let middle = page.count / 2
                result.append(contentsOf: paginate(Array(page[..<middle]), status: status, stale: stale, updated: updated))
                result.append(contentsOf: paginate(Array(page[middle...]), status: status, stale: stale, updated: updated))
            }
        }
        return result
    }

    private func dwellSeconds(_ entries: [Entry]) -> Double {
        let font = NSFont.systemFont(ofSize: 12)
        let overflow = entries.map { max(0, ($0.account as NSString).size(withAttributes: [.font: font]).width - 150) }.max() ?? 0
        return max(15, 2 * overflow / 30 + 4)
    }

    private func descriptor(html: String, page: Int, total: Int, shortened: Bool) -> AtollNotchExperienceDescriptor {
        let footnote = (shortened ? "Some long labels were shortened · " : "") + "Page \(page) of \(max(total, page))"
        let web = AtollWidgetWebContentDescriptor(html: html, preferredHeight: 380, isTransparent: true, allowLocalhostRequests: false, allowRemoteRequests: false, maximumContentWidth: 420)
        let tab = AtollNotchExperienceDescriptor.TabConfiguration(title: "CPA Widget", iconSymbolName: "server.rack", preferredHeight: 420, sections: [], webContent: web, allowWebInteraction: true, contentLayout: .contentOnly, footnote: String(footnote.prefix(140)))
        return AtollNotchExperienceDescriptor(id: "cpa-widget-quotas", bundleIdentifier: Self.bundleID, priority: .normal, accentColor: Self.blue, tab: tab)
    }

    private func htmlPage(entries: [Entry], page: Int, total: Int, status: String, stale: Bool, updated: Date?) -> String {
        let cards = entries.map(card).joined()
        let banner = stale ? "<div class='banner'>Snapshot is stale · Last success: \(escape(updated?.formatted(date: .abbreviated, time: .shortened) ?? "unknown"))</div>" : ""
        let empty = status.isEmpty ? "" : "<div class='empty'>\(escape(status))</div>"
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'none'; img-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'"><meta name="viewport" content="width=device-width,initial-scale=1"><style>
        :root{color-scheme:light dark;font:12px -apple-system,BlinkMacSystemFont,sans-serif;color:CanvasText}*{box-sizing:border-box}body{margin:0;background:transparent;padding:10px}.banner{color:#d98200;font-weight:600;margin-bottom:6px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}.card{min-width:0;height:166px;border:1px solid rgba(128,128,128,.3);border-radius:12px;padding:9px;background:rgba(128,128,128,.08);overflow:hidden}.provider{font-weight:700;font-size:11px;color:#3982ed;margin-bottom:7px}.namebox{height:18px;width:100%;overflow:hidden;white-space:nowrap;font-weight:600}.name{display:inline-block;white-space:nowrap;will-change:transform}.meta{font-size:10px;color:GrayText;margin-top:4px}.gauge{display:flex;align-items:center;gap:7px;margin-top:8px}.ring{width:28px;height:28px;transform:rotate(-90deg)}.pct{font-size:12px;font-weight:700}.empty{height:330px;display:grid;place-items:center;font-weight:600;text-align:center}.footer{text-align:right;color:GrayText;font-size:10px;margin-top:5px}@media(prefers-reduced-motion:reduce){.name{max-width:100%;overflow:hidden;text-overflow:ellipsis}}
        </style></head><body>\(banner)\(empty)<div class="grid">\(cards)</div><div class="footer">\(page) / \(total)</div><script>document.querySelectorAll('.namebox').forEach((b,i)=>{const n=b.querySelector('.name');const overflow=n.scrollWidth-b.clientWidth;if(overflow<=1||matchMedia('(prefers-reduced-motion: reduce)').matches)return;const seconds=overflow/30+2;const dwell=200/seconds;const turn=(200+100*overflow/30)/seconds;const s=document.createElement('style');s.textContent='@keyframes marquee'+i+'{0%,'+dwell+'%{transform:translateX(0)}'+turn+'%,100%{transform:translateX(calc(-1 * var(--overflow)))}}';document.head.append(s);n.style.animation='marquee'+i+' '+seconds+'s linear infinite alternate';n.style.setProperty('--overflow',overflow+'px')});</script></body></html>
        """
    }

    private func card(_ entry: Entry) -> String {
        let frac = entry.fraction
        let gauge: String
        if let frac {
            let color = hex(colorFor(frac))
            let offset = 2 * Double.pi * 10 * (1 - frac)
            gauge = "<svg class='ring' viewBox='0 0 24 24' aria-hidden='true'><circle cx='12' cy='12' r='10' fill='none' stroke='rgba(128,128,128,.25)' stroke-width='3'/><circle cx='12' cy='12' r='10' fill='none' stroke='\(color)' stroke-width='3' stroke-dasharray='62.83' stroke-dashoffset='\(offset)'/></svg><span class='pct'>\(percentText(frac)) remaining</span>"
        } else { gauge = "<span class='pct'>Unavailable</span>" }
        let account = bound(entry).account
        return "<section class='card'><div class='provider'>\(escape(entry.provider))</div><div class='namebox' title='\(escape(account))'><span class='name'>\(escape(account))</span></div><div class='meta'>\(escape(entry.window))</div><div class='gauge' aria-label='\(escape(percentText(frac))) remaining'>\(gauge)</div><div class='meta'>\(escape(entry.resetText ?? "Reset unavailable"))</div></section>"
    }

    private func resetText(_ value: String?) -> String? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) ?? fractionalFormatter.date(from: value) {
            return "Resets \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return value
    }

    private func colorFor(_ value: Double) -> AtollColorDescriptor {
        if value < 0.30 { return AtollColorDescriptor(red: 0.88, green: 0.20, blue: 0.20) }
        if value < 0.70 { return AtollColorDescriptor(red: 0.93, green: 0.55, blue: 0.08) }
        return AtollColorDescriptor(red: 0.18, green: 0.68, blue: 0.35)
    }

    private func hex(_ color: AtollColorDescriptor) -> String {
        String(format: "#%02x%02x%02x", Int(color.red * 255), Int(color.green * 255), Int(color.blue * 255))
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "Unavailable" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }

    private func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(0, limit - 1))) + "…"
    }

    private func bound(_ entry: Entry) -> Entry {
        Entry(selection: entry.selection, provider: truncate(entry.provider, limit: 512), account: truncate(entry.account, limit: 512), window: truncate(entry.window, limit: 512), fraction: entry.fraction, resetText: entry.resetText.map { truncate($0, limit: 512) })
    }

    private func isShortened(_ entry: Entry) -> Bool {
        [entry.provider, entry.account, entry.window, entry.resetText ?? ""].contains { $0.count > 512 }
    }
}
