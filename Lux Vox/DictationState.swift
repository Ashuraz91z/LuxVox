//
//  DictationState.swift
//  Lux Vox
//

import Foundation

/// Les quatre états de l'app (DA §3).
///
/// Deux variables portent l'apparence : le remplissage de la capsule (l'app
/// dort ou travaille) et la forme de l'arceau (ce qu'elle fait). L'état se lit
/// à la forme, jamais à la couleur.
nonisolated enum DictationState: String, CaseIterable, Sendable {
    /// Un micro posé. L'overlay n'est pas affiché.
    case repos
    /// La touche est tenue, le micro capte.
    case ecoute
    /// Micro ouvert sans les mains, jusqu'à un nouvel appui.
    case ecouteVerrouillee
    /// Transcription et nettoyage en cours.
    case traitement

    /// Le glyphe ne s'affiche que lorsqu'il a quelque chose à dire. Un visuel
    /// permanent dans le champ de vision périphérique est une nuisance.
    var estVisible: Bool { self != .repos }

    /// La capsule est pleine quand l'app capte, creuse sinon.
    var capsulePleine: Bool {
        self == .ecoute || self == .ecouteVerrouillee
    }

    /// L'arc que dessine l'arceau, en degrés.
    ///
    /// **Écart assumé avec la DA §3**, à la demande explicite : l'écoute
    /// verrouillée y était dessinée arceau fermé en anneau, pour être le seul
    /// état qui se remarque sans être cherché. Les deux écoutes partagent
    /// désormais le même glyphe ; ce qui les sépare à l'écran est la durée —
    /// le glyphe du double-appui reste tant que le micro est ouvert, celui du
    /// maintien disparaît au relâchement. Le mode reste nommé dans le panneau
    /// déroulant, qui garde donc l'information.
    var arceau: ArceauAngles {
        switch self {
        case .repos, .ecoute, .ecouteVerrouillee:
            ArceauAngles(debut: 0, fin: 180)
        case .traitement:
            // Le seul état asymétrique des quatre : à cette taille,
            // l'asymétrie se repère avant la forme.
            ArceauAngles(debut: 90, fin: 180)
        }
    }
}

/// Les bornes de l'arc, extraites du dessin pour que le choix d'apparence se
/// vérifie sans rendre la vue.
nonisolated struct ArceauAngles: Equatable, Sendable {
    let debut: Double
    let fin: Double
}
