//
//  OverlayController.swift
//  Lux Vox
//

import AppKit
import SwiftUI

/// L'état affiché par l'overlay, observé par la vue pour que les transitions
/// de la DA (§8) s'animent au lieu de sauter.
@MainActor
@Observable
final class OverlayModel {
    var etat: DictationState = .repos
}

/// Le petit visuel flottant, en bas de l'écran.
///
/// Contrainte non négociable : ce panneau **ne prend jamais le focus**. Une
/// dictée qui déplacerait le focus clavier écrirait ensuite dans la mauvaise
/// fenêtre — précisément ce que le principe directeur interdit. D'où le
/// `.nonactivatingPanel`, `canBecomeKey` à `false` et l'indifférence à la
/// souris : rien de ce panneau n'est cliquable, il ne fait qu'informer.
@MainActor
final class OverlayController {

    private let modele = OverlayModel()
    private var panneau: NSPanel?

    /// Assez petit pour rester en périphérie : tout ce qui attire l'attention
    /// plus que nécessaire est un défaut.
    private static let cote: CGFloat = 44
    private static let margeBasse: CGFloat = 28

    func affiche(_ etat: DictationState) {
        modele.etat = etat

        guard etat.estVisible else {
            panneau?.orderOut(nil)
            return
        }

        let panneau = panneauExistantOuNouveau()
        positionne(panneau)
        // `orderFrontRegardless` plutôt que `makeKeyAndOrderFront` : on montre
        // sans jamais activer l'app.
        panneau.orderFrontRegardless()
    }

    func masque() {
        modele.etat = .repos
        panneau?.orderOut(nil)
    }

    private func panneauExistantOuNouveau() -> NSPanel {
        if let panneau { return panneau }

        let nouveau = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.cote, height: Self.cote),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        nouveau.isFloatingPanel = true
        nouveau.level = .statusBar
        nouveau.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        nouveau.isOpaque = false
        nouveau.backgroundColor = .clear
        nouveau.hasShadow = false
        nouveau.ignoresMouseEvents = true
        nouveau.hidesOnDeactivate = false
        nouveau.isReleasedWhenClosed = false
        nouveau.contentView = NSHostingView(rootView: OverlayView(modele: modele))

        panneau = nouveau
        return nouveau
    }

    /// Bas de l'écran actif, centré. `visibleFrame` tient compte du Dock, donc
    /// l'overlay ne se glisse jamais dessous.
    private func positionne(_ panneau: NSPanel) {
        guard let ecran = NSScreen.main ?? NSScreen.screens.first else { return }
        let zone = ecran.visibleFrame
        panneau.setFrameOrigin(
            NSPoint(
                x: zone.midX - Self.cote / 2,
                y: zone.minY + Self.margeBasse
            )
        )
    }
}

/// La pastille qui porte le glyphe.
///
/// Pas d'ombre — le design system Mac les proscrit. La lisibilité au-dessus
/// d'un contenu quelconque vient d'un fond opaque et d'un filet `separator`,
/// pas d'une élévation.
private struct OverlayView: View {
    @Bindable var modele: OverlayModel
    @Environment(\.colorScheme) private var theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LuxColor.rayon, style: .continuous)
                .fill(LuxColor.surfaceElevated(theme))
                .overlay(
                    RoundedRectangle(cornerRadius: LuxColor.rayon, style: .continuous)
                        .stroke(LuxColor.separator(theme), lineWidth: 1)
                )

            VoxGlyph(etat: modele.etat, taille: 24)
        }
        .padding(2)
        .opacity(modele.etat.estVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: modele.etat.estVisible)
    }
}
