import WidgetKit
import SwiftUI

@main
struct ClockedWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ClockedSmallWidget()
        #if canImport(ActivityKit)
        ClockedLiveActivity()
        #endif
    }
}
