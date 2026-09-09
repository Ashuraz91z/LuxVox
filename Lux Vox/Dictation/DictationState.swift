//
//  DictationState.swift
//  Lux Vox
//

import Foundation

/// Les quatre états de l'app (DA §3).
///
/// Une seule variable porte l'apparence : `signal`. Le HUD ne dessine plus un
/// glyphe à quatre visages mais une bande de niveaux, et une bande n'a que
/// trois choses à dire — elle dort, elle suit la voix, elle travaille.
nonisolated enum DictationState: String, CaseIterable, Sendable {
    /// Un micro posé. L'overlay n'est pas affiché.
    case repos
    /// La touche est tenue, le micro capte.
    case ecoute
    /// Micro ouvert sans les mains, jusqu'à un nouvel appui.
    case ecouteVerrouillee
    /// Transcription et nettoyage en cours.
    case traitement

    /// Le HUD ne s'affiche que lorsqu'il a quelque chose à dire. Un visuel
    /// permanent dans le champ de vision périphérique est une nuisance.
    var estVisible: Bool { self != .repos }

    /// Ce que la bande de niveaux montre.
    ///
    /// **Écart assumé avec la DA §3**, à la demande explicite : l'écoute
    /// verrouillée y avait sa propre forme, pour être le seul état qui se
    /// remarque sans être cherché. Les deux écoutes partagent désormais la
    /// même apparence ; ce qui les sépare à l'écran est la durée — le HUD du
    /// double-appui reste tant que le micro est ouvert, celui du maintien
    /// disparaît au relâchement. Le mode reste nommé dans le panneau
    /// déroulant, qui garde donc l'information.
    var signal: Signal {
        switch self {
        case .repos: .eteint
        case .ecoute, .ecouteVerrouillee: .capte
        case .traitement: .travaille
        }
    }

    /// Les trois régimes de la bande.
    nonisolated enum Signal: Equatable, Sendable {
        /// Rien à montrer.
        case eteint
        /// Les traits suivent le micro, mesure par mesure.
        case capte
        /// Plus de voix à montrer : une onde traverse la bande pour dire que
        /// ça travaille.
        case travaille
    }
}
