//
//  LuxColor.swift
//  Lux Vox
//

import SwiftUI

/// Les jetons de la DA (§5), résolus explicitement selon le thème plutôt que
/// par une couleur dynamique : à ce nombre de jetons, un `switch` lisible vaut
/// mieux qu'un jeu de colorsets.
///
/// L'ardoise et le halo sont l'accent propre à Lux Vox — la seule famille de
/// teintes froide de la palette Lux, et celle du signal.
nonisolated enum LuxColor {

    static func accent(_ theme: ColorScheme) -> Color {
        theme == .dark ? Color(hex: 0x8FB9C4) : Color(hex: 0x4A7C8C)
    }

    static func surfaceElevated(_ theme: ColorScheme) -> Color {
        theme == .dark ? Color(hex: 0x263329) : Color(hex: 0xFFFFFF)
    }

    static func text(_ theme: ColorScheme) -> Color {
        theme == .dark ? Color(hex: 0xF0EEE6) : Color(hex: 0x1D1D1F)
    }

    static func textSecondary(_ theme: ColorScheme) -> Color {
        theme == .dark ? Color(hex: 0xA9B8AB) : Color(hex: 0x5B6B5E)
    }

    static func textTertiary(_ theme: ColorScheme) -> Color {
        theme == .dark ? Color(hex: 0x75817A) : Color(hex: 0x8B9389)
    }

    static func separator(_ theme: ColorScheme) -> Color {
        theme == .dark ? Color(hex: 0x2C3A32) : Color(hex: 0xDCD7C8)
    }

    /// Un seul usage prévu : la mention « saisie sécurisée — non injecté ».
    static func important(_ theme: ColorScheme) -> Color {
        theme == .dark ? Color(hex: 0xF4A261) : Color(hex: 0xC4703A)
    }

    /// Rayon unique de la DA (§7). La capsule sur Mac est la signature d'un
    /// portage iOS.
    static let rayon: CGFloat = 6
}

extension Color {
    fileprivate nonisolated init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
