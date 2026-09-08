//
//  KeyboardTrigger.swift
//  Lux Vox
//

import AppKit
import ApplicationServices

/// Le déclencheur clavier : un `CGEvent` tap qui lit les transitions du
/// modificateur choisi et les traduit en gestes.
///
/// ## Ce que ce tap lit, et ce qu'il n'en fait pas
///
/// Un tap de session voit passer toutes les frappes de l'utilisateur. Celui-ci
/// est donc réduit au minimum utile :
///
/// - le masque ne couvre que `flagsChanged` (les modificateurs) et `keyDown`,
///   les seuls types dont la grammaire de gestes a besoin ;
/// - le seul champ lu est le **code de touche**, comparé au déclencheur et à
///   `Échap`. Aucun caractère, aucune combinaison, aucun contenu de frappe
///   n'est inspecté, conservé, journalisé ni transmis ;
/// - aucun événement n'est retenu au-delà de l'appel.
@MainActor
final class KeyboardTrigger {

    /// Les deux déclencheurs prévus par la décision *b*. Le globe est le choix
    /// par défaut ; le Ctrl droit est le repli si le globe s'avère incapturable
    /// sur la machine — même grammaire de gestes, keycode distinct du Ctrl
    /// gauche, libre de toute réservation système.
    enum Declencheur: String, CaseIterable, Identifiable, Sendable {
        case globe
        case ctrlDroit

        var id: String { rawValue }

        var libelle: String {
            switch self {
            case .globe: "Touche 🌐 (Fn)"
            case .ctrlDroit: "Ctrl droit"
            }
        }

        /// `kVK_Function` et `kVK_RightControl`.
        var keycode: Int64 {
            switch self {
            case .globe: 63
            case .ctrlDroit: 62
            }
        }

        var drapeau: CGEventFlags {
            switch self {
            case .globe: .maskSecondaryFn
            case .ctrlDroit: .maskControl
            }
        }
    }

    /// `kVK_Escape`.
    private static let escape: Int64 = 53

    var declencheur: Declencheur = .globe
    /// Ce que la machine à états demande de faire.
    var onCommande: ((TriggerCommand) -> Void)?

    private(set) var actif = false

    private var machine = TriggerMachine()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var minuterie: DispatchWorkItem?
    /// Échap n'est intercepté que pendant une dictée — sinon on le casserait
    /// dans toutes les autres applications.
    private var sessionEnCours = false

    // MARK: - Permission

    static var accessibiliteAccordee: Bool { AXIsProcessTrusted() }

    /// Déclenche l'alerte système native. La DA (§9) est explicite : une
    /// fenêtre dessinée qui réclamerait ce pouvoir ressemblerait à un logiciel
    /// malveillant.
    static func demandeAccessibilite() {
        // Valeur littérale de `kAXTrustedCheckOptionPrompt` : la constante
        // importée est une variable globale mutable, que la concurrence
        // stricte refuse de laisser lire depuis un contexte isolé.
        let clef = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([clef: true] as CFDictionary)
    }

    // MARK: - Cycle de vie

    @discardableResult
    func demarre() -> Bool {
        guard !actif else { return true }
        guard Self.accessibiliteAccordee else { return false }

        let masque = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        let rappel: CGEventTapCallBack = { _, type, evenement, contexte in
            guard let contexte else { return Unmanaged.passUnretained(evenement) }
            let trigger = Unmanaged<KeyboardTrigger>.fromOpaque(contexte).takeUnretainedValue()

            // Seuls des scalaires franchissent la frontière d'isolation :
            // `CGEvent` n'est pas `Sendable`, et le faire traverser serait
            // exactement le genre d'accès concurrent que le mode Swift 6 est
            // là pour refuser. L'événement lui-même reste dans ce rappel.
            let keycode = evenement.getIntegerValueField(.keyboardEventKeycode)
            let drapeaux = evenement.flags.rawValue

            // La source est installée sur la boucle principale : ce rappel
            // s'exécute donc bien sur le `MainActor`.
            let consomme = MainActor.assumeIsolated {
                trigger.traite(type: type.rawValue, keycode: keycode, drapeaux: drapeaux)
            }
            return consomme ? nil : Unmanaged.passUnretained(evenement)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(masque),
            callback: rappel,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = source
        actif = true
        return true
    }

    func arrete() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        actif = false
        desarmeMinuterie()
    }

    // MARK: - Traitement des événements

    /// Renvoie `true` si l'événement doit être consommé.
    private func traite(type: UInt32, keycode: Int64, drapeaux: UInt64) -> Bool {
        switch CGEventType(rawValue: type) {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS désarme un tap trop lent ou lors d'une saisie protégée.
            // Sans cette réactivation, le déclencheur meurt en silence.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false

        case .flagsChanged:
            guard keycode == declencheur.keycode else { return false }
            let enfonce = CGEventFlags(rawValue: drapeaux).contains(declencheur.drapeau)
            envoie(enfonce ? .appui(maintenant) : .relachement(maintenant))
            // Volontairement **non consommé** : voir la note en fin de fichier.
            return false

        case .keyDown:
            guard sessionEnCours, keycode == Self.escape else { return false }
            envoie(.echap(maintenant))
            // Consommé, et seulement ici : l'Échap qui annule une dictée n'a
            // pas à atteindre aussi l'application au premier plan, où il
            // fermerait une feuille ou viderait un champ.
            return true

        default:
            return false
        }
    }

    private var maintenant: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func envoie(_ evenement: TriggerEvent) {
        for commande in machine.traite(evenement) {
            switch commande {
            case .armerMinuterie(let delai):
                armeMinuterie(delai)
            case .desarmerMinuterie:
                desarmeMinuterie()
            case .demarrer:
                sessionEnCours = true
                onCommande?(commande)
            case .terminer, .annuler:
                sessionEnCours = false
                onCommande?(commande)
            case .verrouiller:
                onCommande?(commande)
            }
        }
    }

    private func armeMinuterie(_ delai: TimeInterval) {
        desarmeMinuterie()
        let tache = DispatchWorkItem { [weak self] in
            guard let self else { return }
            envoie(.minuterie(maintenant))
        }
        minuterie = tache
        DispatchQueue.main.asyncAfter(deadline: .now() + delai, execute: tache)
    }

    private func desarmeMinuterie() {
        minuterie?.cancel()
        minuterie = nil
    }
}

// MARK: - Pourquoi le déclencheur n'est pas consommé
//
// Le cahier des charges prévoyait un `headInsertEventTap` pour intercepter la
// touche et l'empêcher d'atteindre l'application au premier plan. Le tap est
// bien en tête de chaîne, mais l'événement est laissé passer, pour une raison
// que la rédaction du cahier n'avait pas en vue : 🌐 et Ctrl droit sont des
// **modificateurs**, pas des touches ordinaires. Avaler leur `flagsChanged`
// reviendrait à casser toutes les combinaisons qui en dépendent — Fn+F1…F12,
// Fn+flèches, Fn+Suppr, et tout raccourci au Ctrl droit.
//
// Ce que le cahier voulait vraiment neutraliser, c'est l'action que macOS
// attache à la touche (dictée Apple, sélecteur d'emoji). Elle se règle dans
// Réglages Système → Clavier, ce que l'onboarding doit de toute façon guider.
// Aucune application ordinaire n'agit sur 🌐 seul : le laisser passer est sans
// conséquence, l'avaler ne l'est pas.
