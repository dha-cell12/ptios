import SwiftUI
import WidgetKit

private struct TLinkBootEntry: TimelineEntry {
    let date: Date
    let status: String
}

private struct TLinkBootProvider: TimelineProvider {
    func placeholder(in context: Context) -> TLinkBootEntry {
        TLinkBootEntry(date: Date(), status: "preview")
    }

    func getSnapshot(in context: Context, completion: @escaping (TLinkBootEntry) -> Void) {
        let status = context.isPreview ? "preview" : TLinkWidgetWakeHelper.wakeHostApplicationIfNecessary()
        completion(TLinkBootEntry(date: Date(), status: status))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TLinkBootEntry>) -> Void) {
        let status = TLinkWidgetWakeHelper.wakeHostApplicationIfNecessary()
        let entry = TLinkBootEntry(date: Date(), status: status)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 5, to: entry.date)
            ?? entry.date.addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

private struct TLinkBootWidgetView: View {
    let entry: TLinkBootEntry

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color(red: 0.08, green: 0.12, blue: 0.20),
                                            Color(red: 0.08, green: 0.38, blue: 0.52)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
                Text("TLinkauto")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(entry.status.replacingOccurrences(of: "_", with: " "))
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.78))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

@main
struct TLinkBootWidget: Widget {
    private let kind = "com.tlinkauto.streamcontrol.bootwidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TLinkBootProvider()) { entry in
            TLinkBootWidgetView(entry: entry)
        }
        .configurationDisplayName("TLinkauto Boot Wake")
        .description("Wakes the TrollStore runtime; Boot Script controls which script runs afterward.")
        .supportedFamilies([.systemSmall])
    }
}
