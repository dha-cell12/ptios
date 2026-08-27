import SwiftUI
import WidgetKit

private struct TLinkBootEntry: TimelineEntry {
    let date: Date
}

private struct TLinkBootProvider: TimelineProvider {
    func placeholder(in context: Context) -> TLinkBootEntry {
        TLinkBootEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (TLinkBootEntry) -> Void) {
        completion(TLinkBootEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TLinkBootEntry>) -> Void) {
        TLinkWidgetWakeHelper.wakeHostApplicationIfNecessary()
        let entry = TLinkBootEntry(date: Date())
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
                Text("Boot wake ready")
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.78))
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
        .description("Wakes the TrollStore runtime after reboot when Boot Script is enabled.")
        .supportedFamilies([.systemSmall])
    }
}
