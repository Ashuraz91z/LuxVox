//
//  TriggerGesture.swift
//  Lux Vox
//

import Foundation

/// Ce que le déclencheur clavier produit comme événements bruts.
///
/// Les horodatages sont fournis par l'appelant plutôt que lus depuis une
/// horloge : c'est ce qui rend la grammaire de gestes vérifiable sans clavier,
/// sans permission et sans attendre en temps réel.
nonisolated enum TriggerEvent: Equatable, Sendable {
    case appui(TimeInterval)
    case relachement(TimeInterval)
    case echap(TimeInterval)
    /// L'échéance précédemment armée est arrivée.
    case minuterie(TimeInterval)
}

/// Ce que la machine demande au reste de l'app.
nonisolated enum TriggerCommand: Equatable, Sendable {
    case demarrer
    case verrouiller
    case terminer
    case annuler
    case armerMinuterie(TimeInterval)
    case desarmerMinuterie
}

/// La grammaire de gestes de la décision *b* du cahier des charges, isolée dans
/// une machine à états pure.
///
/// Une seule touche, deux gestes :
///
/// | Geste | Effet |
/// |---|---|
/// | Maintien au-delà du seuil | Enregistre tant que la touche est tenue |
/// | Deux appuis sous le seuil | Mode verrouillé, sans les mains |
/// | Appui simple, en verrouillé | Ferme et transcrit |
/// | Échap | Annule : rien n'est transcrit, rien n'est injecté |
///
/// Lever l'ambiguïté du premier appui coûte le seuil : un appui plus court
/// n'est jamais une dictée — personne ne dit rien en 300 ms — et l'app attend
/// un second appui avant de conclure. Au-delà du seuil il n'y a plus
/// d'ambiguïté, et aucun délai n'est ajouté.
nonisolated struct TriggerMachine {

    /// Seuil unique des deux gestes (cahier des charges, §6 décision *b*).
    static let seuil: TimeInterval = 0.3

    private enum Phase: Equatable {
        case repos
        /// Appui en cours, on ne sait pas encore si c'est un maintien.
        case qualification
        /// Le seuil est franchi : dictée en cours, touche tenue.
        case maintien
        /// Un appui court vient de se terminer, un second le suivra peut-être.
        case attenteSecondAppui(finPremier: TimeInterval)
        case verrouille
    }

    private var phase: Phase = .repos

    /// Là où en est la machine, pour l'affichage.
    var etat: DictationState {
        switch phase {
        case .repos, .qualification, .attenteSecondAppui: .repos
        case .maintien: .ecoute
        case .verrouille: .ecouteVerrouillee
        }
    }

    /// Fait avancer la machine et renvoie ce qu'il y a à faire.
    mutating func traite(_ evenement: TriggerEvent) -> [TriggerCommand] {
        switch (phase, evenement) {

        // Repos — seul un appui ouvre quelque chose.
        case (.repos, .appui):
            phase = .qualification
            return [.armerMinuterie(Self.seuil)]

        // Qualification — maintien ou premier appui d'un double ?
        case (.qualification, .minuterie):
            phase = .maintien
            return [.demarrer]

        case (.qualification, .relachement(let t)):
            // Trop court pour être une dictée : le fragment est jeté.
            phase = .attenteSecondAppui(finPremier: t)
            return [.armerMinuterie(Self.seuil)]

        case (.qualification, .echap):
            phase = .repos
            return [.desarmerMinuterie]

        // Maintien — le relâchement conclut, Échap annule.
        case (.maintien, .relachement):
            phase = .repos
            return [.terminer]

        case (.maintien, .echap):
            phase = .repos
            return [.annuler]

        // Attente d'un second appui.
        case (.attenteSecondAppui(let finPremier), .appui(let t)):
            if t - finPremier < Self.seuil {
                phase = .verrouille
                return [.desarmerMinuterie, .demarrer, .verrouiller]
            }
            // Trop tard pour un double : c'est le début d'un nouveau geste.
            phase = .qualification
            return [.armerMinuterie(Self.seuil)]

        case (.attenteSecondAppui, .minuterie):
            // Un appui court isolé ne déclenche rien.
            phase = .repos
            return []

        case (.attenteSecondAppui, .echap):
            phase = .repos
            return [.desarmerMinuterie]

        // Verrouillé — un appui simple referme.
        case (.verrouille, .appui):
            phase = .repos
            return [.terminer]

        case (.verrouille, .echap):
            phase = .repos
            return [.annuler]

        // Tout le reste est sans effet : relâchements orphelins (celui du
        // second appui d'un double, celui qui suit la fermeture) et minuteries
        // périmées.
        default:
            return []
        }
    }
}
