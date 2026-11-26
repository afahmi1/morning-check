import SwiftUI

struct DayBreakBrand: View {
    let iconSize: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image("DayBreakLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.24))
                .accessibilityHidden(true)
            Text("DayBreak")
        }
    }
}
