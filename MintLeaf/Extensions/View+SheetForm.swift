import SwiftUI

extension View {
    func macOSSheet(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        self
            .frame(width: width, height: height)
            .background(.background)
        #else
        self
        #endif
    }
}
