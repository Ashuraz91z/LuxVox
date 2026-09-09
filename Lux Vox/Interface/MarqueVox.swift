//
//  MarqueVox.swift
//  Lux Vox
//

import SwiftUI

/// La marque de Lux Vox : quatre traits dressés, quatre longueurs.
///
/// **Révision de la DA §2.2** : le micro dessiné — capsule, arceau, pied — a
/// été retiré. Il décrivait l'objet et pas le produit ; à 16 pt il perdait ses
/// trois pièces et redevenait une tache ; et il ne pouvait pas cohabiter avec
/// la bande de niveaux du HUD, qui est ce que l'utilisateur regarde vraiment.
///
/// Ce qui le remplace tient les trois invariants de famille (DA §2.1) — du
/// plein jamais du trait, des bouts entièrement arrondis, une primitive
/// répétée — et les tient mieux : c'est littéralement la même primitive que le
/// HUD, arrêtée sur une image. Md a quatre barres à quatre longueurs ; Vox a
/// les siennes, mais dressées et en dégradé, parce que chez lui elles bougent.
struct MarqueVox: View {
    var taille: CGFloat = 22

    @Environment(\.colorScheme) private var theme

    /// Les quatre longueurs, en part de la hauteur. Aucune n'est répétée :
    /// c'est ce qui fait lire un signal plutôt qu'un peigne.
    private static let longueurs: [CGFloat] = [0.42, 0.86, 1, 0.58]
    private static let opacites: [Double] = [0.45, 0.75, 1, 0.6]

    var body: some View {
        HStack(alignment: .center, spacing: taille * 0.115) {
            ForEach(Array(Self.longueurs.enumerated()), id: \.offset) { rang, longueur in
                Capsule(style: .continuous)
                    .fill(LuxColor.accent(theme))
                    .frame(width: taille * 0.115, height: taille * longueur)
                    .opacity(Self.opacites[rang])
            }
        }
        .frame(width: taille, height: taille)
        .accessibilityHidden(true)
    }
}

#Preview("Marque") {
    HStack(spacing: 24) {
        MarqueVox(taille: 16)
        MarqueVox(taille: 22)
        MarqueVox(taille: 44)
    }
    .padding(24)
}
