import WidgetKit
import SwiftUI

@main
struct HoursWidgetsBundle: WidgetBundle {
    var body: some Widget {
        HoursSmallWidget()
        #if canImport(ActivityKit)
        HoursLiveActivity()
        #endif
    }
}
