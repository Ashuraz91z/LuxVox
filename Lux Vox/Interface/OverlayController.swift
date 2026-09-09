//
//  OverlayController.swift
//  Lux Vox
//

import AppKit
import SwiftUI

/// L'état affiché par l'overlay, observé par la vue.
@MainActor
@Observable
final class OverlayModel {
    var etat: DictationState = .repos
    /// Le niveau du micro, lissé. La vue en tire une valeur à chaque image.
    var niveau = NiveauLisse()
}

/// Ce qui se voit pendant une dictée : une capsule en bas de l'écran, et rien
/// d'autre.
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

    /// Rien ne déborde de la capsule — ni ombre, ni flou. La marge n'est là
    /// que pour laisser respirer l'animation d'entrée.
    static let debord: CGFloat = 6

    private static let margeBasse: CGFloat = 34

    private static var largeur: CGFloat { Vumetre.largeur + debord * 2 }
    private static var hauteur: CGFloat { Vumetre.hauteur + debord * 2 }

    /// Alimente les barres sans rouvrir le panneau : appelé au rythme du micro.
    ///
    /// Le pic de la salve, pas sa moyenne : moyenner 170 ms de parole rabote
    /// l'attaque des syllabes, et c'est justement l'attaque qui fait qu'on
    /// reconnaît sa propre voix dans les barres.
    func mesure(_ nouvelles: [Float]) {
        guard let pic = nouvelles.max() else { return }
        modele.niveau.vise(Double(pic))
    }

    func affiche(_ etat: DictationState) {
        modele.etat = etat
        if etat == .repos { modele.niveau = NiveauLisse() }

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
            contentRect: NSRect(x: 0, y: 0, width: Self.largeur, height: Self.hauteur),
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
                x: zone.midX - Self.largeur / 2,
                y: zone.minY + Self.margeBasse - Self.debord
            )
        )
    }
}

/// **Révision de la DA §7** : plus de verre, plus de dégradé, plus d'ombre.
///
/// Trois couleurs en tout — le noir de la capsule, le crème du trait et des
/// barres, et ce qu'il y a derrière. Tout ce qui a été retiré (le flou du
/// fond, le halo, le liseré dégradé) servait à faire tenir un objet qui se
/// tenait mieux sans.
private struct OverlayView: View {
    @Bindable var modele: OverlayModel

    private var visible: Bool { modele.etat.estVisible }

    var body: some View {
        Vumetre(signal: modele.etat.signal, niveau: modele.niveau)
            .padding(OverlayController.debord)
            // La capsule s'ouvre depuis le centre au lieu d'apparaître : le
            // geste dure moins qu'un clignement et évite le surgissement.
            .scaleEffect(visible ? 1 : 0.86, anchor: .center)
            .opacity(visible ? 1 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: visible)
    }
}

#Preview("Overlay") {
    let modele = OverlayModel()
    OverlayView(modele: modele)
        .padding(30)
        .background(Color(white: 0.14))
        .task { modele.etat = .ecoute }
}
