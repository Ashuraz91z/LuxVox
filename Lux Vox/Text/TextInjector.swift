//
//  TextInjector.swift
//  Lux Vox
//

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import os

/// L'injection du texte à l'emplacement du curseur (décision *c* du cahier
/// des charges).
///
/// Deux stratégies, et surtout deux garde-fous. Le principe directeur pèse plus
/// lourd que la fonctionnalité : **ne rien écrire vaut mieux qu'écrire au
/// mauvais endroit**. Un refus n'est pas une panne — le texte reste dans
/// l'historique, d'où il se copie à la main.
@MainActor
final class TextInjector {

    /// Pourquoi on n'a rien écrit.
    enum Refus: Equatable {
        case saisieSecurisee
        case fenetreChangee(String?)
        case accessibiliteRefusee
        case texteVide

        var explication: String {
            switch self {
            case .saisieSecurisee:
                "Saisie sécurisée active — rien n'a été écrit."
            case .fenetreChangee(let nom):
                if let nom {
                    "La fenêtre a changé (\(nom)) — rien n'a été écrit."
                } else {
                    "La fenêtre a changé — rien n'a été écrit."
                }
            case .accessibiliteRefusee:
                "Permission Accessibilité manquante — rien n'a été écrit."
            case .texteVide:
                "Rien à écrire."
            }
        }
    }

    enum Resultat: Equatable {
        case injecte
        case refuse(Refus)
    }

    /// Au-delà de cette longueur, la frappe simulée devient trop lente et l'on
    /// passe par le presse-papier.
    nonisolated static let seuilPressePapier = 200

    /// Les applications Electron et les terminaux perdent des événements
    /// synthétiques envoyés trop vite. On les sert par petits paquets.
    nonisolated static let taillePaquet = 20

    /// Respiration entre deux paquets.
    nonisolated static let pauseEntrePaquets = Duration.milliseconds(8)

    /// Laps laissé à l'application cible pour lire le presse-papier avant
    /// qu'on y remette ce qui s'y trouvait.
    nonisolated static let delaiAvantRestauration = Duration.milliseconds(250)

    private let journal = Logger(subsystem: "lux-audere.Lux-Vox", category: "injection")

    /// L'application visée, relevée au début de la dictée.
    ///
    /// Écrire dans la mauvaise fenêtre est pire que ne rien écrire (§7) : on
    /// compare donc à l'arrivée, et on renonce si le focus a bougé entre-temps.
    func cibleActuelle() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func injecte(_ texte: String, vers cible: pid_t?) async -> Resultat {
        guard !texte.isEmpty else { return .refuse(.texteVide) }

        guard AXIsProcessTrusted() else {
            journal.error("injection refusée : accessibilité")
            return .refuse(.accessibiliteRefusee)
        }

        // Un champ de saisie protégée a le focus : le texte dicté n'a rien à y
        // faire, et il ne doit pas non plus transiter par le presse-papier.
        guard !IsSecureEventInputEnabled() else {
            journal.error("injection refusée : saisie sécurisée")
            return .refuse(.saisieSecurisee)
        }

        let maintenant = NSWorkspace.shared.frontmostApplication
        if let cible, maintenant?.processIdentifier != cible {
            journal.error("injection refusée : la fenêtre a changé")
            return .refuse(.fenetreChangee(maintenant?.localizedName))
        }

        if texte.count > Self.seuilPressePapier {
            await colle(texte)
        } else {
            await frappe(texte)
        }

        journal.info("injecté : \(texte.count, privacy: .public) caractères")
        return .injecte
    }

    // MARK: - Frappe simulée

    /// `keyboardSetUnicodeString` plutôt qu'un code de touche : indépendant de
    /// la disposition du clavier, et les accents passent correctement.
    private func frappe(_ texte: String) async {
        let source = CGEventSource(stateID: .privateState)
        let paquets = Self.paquets(de: texte)

        for (rang, paquetImmuable) in paquets.enumerated() {
            var paquet = paquetImmuable

            for enfonce in [true, false] {
                guard let evenement = CGEvent(
                    keyboardEventSource: source, virtualKey: 0, keyDown: enfonce
                ) else { continue }
                evenement.keyboardSetUnicodeString(stringLength: paquet.count, unicodeString: &paquet)
                evenement.post(tap: .cgAnnotatedSessionEventTap)
            }

            if rang < paquets.count - 1 {
                try? await Task.sleep(for: Self.pauseEntrePaquets)
            }
        }
    }

    /// Découpe le texte en paquets d'unités UTF-16.
    ///
    /// Le découpage se fait sur l'UTF-16 parce que c'est ce que
    /// `keyboardSetUnicodeString` consomme. Une paire de substitution — un
    /// émoji, par exemple — ne doit jamais être coupée en deux : la moitié
    /// envoyée seule n'est pas un caractère valide.
    nonisolated static func paquets(de texte: String) -> [[UniChar]] {
        var paquets: [[UniChar]] = []
        var courant: [UniChar] = []

        for scalaire in texte.unicodeScalars {
            let unites = Array(String(scalaire).utf16)
            if courant.count + unites.count > taillePaquet, !courant.isEmpty {
                paquets.append(courant)
                courant = []
            }
            courant.append(contentsOf: unites)
        }
        if !courant.isEmpty { paquets.append(courant) }
        return paquets
    }

    // MARK: - Presse-papier

    /// Colle, puis **rend le presse-papier tel qu'on l'a trouvé** : l'utilisateur
    /// n'a pas demandé qu'on écrase ce qu'il y avait mis.
    private func colle(_ texte: String) async {
        let planche = NSPasteboard.general
        let sauvegarde = contenu(de: planche)

        planche.clearContents()
        planche.setString(texte, forType: .string)

        posteCommandeV()

        try? await Task.sleep(for: Self.delaiAvantRestauration)
        restaure(sauvegarde, dans: planche)
    }

    private func posteCommandeV() {
        let source = CGEventSource(stateID: .privateState)
        let v = CGKeyCode(kVK_ANSI_V)

        for enfonce in [true, false] {
            guard let evenement = CGEvent(
                keyboardEventSource: source, virtualKey: v, keyDown: enfonce
            ) else { continue }
            evenement.flags = .maskCommand
            evenement.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private func contenu(de planche: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (planche.pasteboardItems ?? []).map { element in
            var copie: [NSPasteboard.PasteboardType: Data] = [:]
            for type in element.types {
                if let donnees = element.data(forType: type) {
                    copie[type] = donnees
                }
            }
            return copie
        }
    }

    private func restaure(
        _ sauvegarde: [[NSPasteboard.PasteboardType: Data]],
        dans planche: NSPasteboard
    ) {
        planche.clearContents()
        guard !sauvegarde.isEmpty else { return }

        let elements: [NSPasteboardItem] = sauvegarde.map { copie in
            let element = NSPasteboardItem()
            for (type, donnees) in copie {
                element.setData(donnees, forType: type)
            }
            return element
        }
        planche.writeObjects(elements)
    }
}
