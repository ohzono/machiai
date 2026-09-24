import SwiftUI

extension Animation {
    /// Core Animation's easeInEaseOut. The default curve for every Machiai motion.
    static let machiai = Animation.timingCurve(0.42, 0, 0.58, 1, duration: 0.35)
}

/// "2 minutes ago" that keeps itself current.
struct RelativeTimeText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            Text(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                .id(context.date)
        }
    }
}
