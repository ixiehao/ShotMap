import SwiftUI

/// Shared workspace surfaces for the main window and the manual frame editor.
struct StudioPalette {
    let isLight: Bool

    var window: Color {
        isLight ? Color(red: 0.969, green: 0.973, blue: 0.980)
                : Color(red: 0.063, green: 0.075, blue: 0.090)
    }

    var panel: Color {
        isLight ? Color(red: 0.973, green: 0.976, blue: 0.980)
                : Color(red: 0.102, green: 0.110, blue: 0.122)
    }

    var canvas: Color {
        isLight ? Color(red: 0.937, green: 0.949, blue: 0.965)
                : Color(red: 0.071, green: 0.086, blue: 0.110)
    }

    var control: Color {
        isLight ? .white : Color(red: 0.114, green: 0.137, blue: 0.173)
    }

    var divider: Color { isLight ? .black.opacity(0.12) : .white.opacity(0.13) }
    var accent: Color {
        isLight ? SelectionPalette.active : Color(red: 0.353, green: 0.655, blue: 1)
    }
}
