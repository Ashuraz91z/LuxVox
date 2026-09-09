//
//  TriggerGestureTests.swift
//  Lux VoxTests
//

import Testing
@testable import Lux_Vox

/// La grammaire de gestes de la décision *b*, vérifiée sans clavier, sans
/// permission Accessibilité et sans attendre en temps réel : les horodatages
/// sont fournis par le test.
///
/// C'est le seul endroit où l'ambiguïté « appui court ou premier d'un double »
/// se règle, et une erreur ici ne se verrait qu'à l'usage, par intermittence.
@Suite("Déclencheur — grammaire de gestes")
struct TriggerGestureTests {

    /// Un peu au-delà et un peu en deçà du seuil de 300 ms.
    static let seuil = TriggerMachine.seuil
    static let court = seuil / 2
    static let long = seuil * 2

    // MARK: - Maintien

    @Test("Maintenir démarre, relâcher transcrit")
    func maintien() {
        var machine = TriggerMachine()

        #expect(machine.traite(.appui(0)) == [.armerMinuterie(Self.seuil)])
        #expect(machine.etat == .repos)

        #expect(machine.traite(.minuterie(Self.seuil)) == [.demarrer])
        #expect(machine.etat == .ecoute)

        #expect(machine.traite(.relachement(2)) == [.terminer])
        #expect(machine.etat == .repos)
    }

    @Test("Échap pendant un maintien annule sans transcrire")
    func echapPendantMaintien() {
        var machine = TriggerMachine()
        _ = machine.traite(.appui(0))
        _ = machine.traite(.minuterie(Self.seuil))

        #expect(machine.traite(.echap(1)) == [.annuler])
        #expect(machine.etat == .repos)
    }

    // MARK: - Double-appui

    @Test("Deux appuis rapprochés verrouillent le micro")
    func doubleAppui() {
        var machine = TriggerMachine()

        _ = machine.traite(.appui(0))
        _ = machine.traite(.relachement(Self.court))
        let commandes = machine.traite(.appui(Self.court * 2))

        #expect(commandes == [.desarmerMinuterie, .demarrer, .verrouiller])
        #expect(machine.etat == .ecouteVerrouillee)
    }

    /// Le second appui est encore enfoncé au moment du verrouillage : son
    /// relâchement ne doit surtout pas refermer le micro qu'il vient d'ouvrir.
    @Test("Le relâchement du second appui ne referme pas")
    func relachementApresVerrouillage() {
        var machine = TriggerMachine()
        _ = machine.traite(.appui(0))
        _ = machine.traite(.relachement(Self.court))
        _ = machine.traite(.appui(Self.court * 2))

        #expect(machine.traite(.relachement(Self.court * 3)).isEmpty)
        #expect(machine.etat == .ecouteVerrouillee)
    }

    @Test("Un appui simple referme le mode verrouillé")
    func fermetureDuVerrouillage() {
        var machine = TriggerMachine()
        _ = machine.traite(.appui(0))
        _ = machine.traite(.relachement(Self.court))
        _ = machine.traite(.appui(Self.court * 2))
        _ = machine.traite(.relachement(Self.court * 3))

        #expect(machine.traite(.appui(10)) == [.terminer])
        #expect(machine.etat == .repos)
        // Le relâchement de cet appui-là ne doit rien rouvrir.
        #expect(machine.traite(.relachement(10.1)).isEmpty)
        #expect(machine.etat == .repos)
    }

    @Test("Échap annule aussi le mode verrouillé")
    func echapPendantVerrouillage() {
        var machine = TriggerMachine()
        _ = machine.traite(.appui(0))
        _ = machine.traite(.relachement(Self.court))
        _ = machine.traite(.appui(Self.court * 2))

        #expect(machine.traite(.echap(5)) == [.annuler])
        #expect(machine.etat == .repos)
    }

    // MARK: - L'ambiguïté des 300 ms

    @Test("Un appui court isolé ne déclenche rien du tout")
    func appuiCourtIsole() {
        var machine = TriggerMachine()
        _ = machine.traite(.appui(0))
        _ = machine.traite(.relachement(Self.court))

        // L'attente expire sans second appui : le fragment est jeté.
        #expect(machine.traite(.minuterie(Self.court + Self.seuil)).isEmpty)
        #expect(machine.etat == .repos)
    }

    @Test("Un appui court ne produit jamais de dictée")
    func appuiCourtNeDemarreJamais() {
        var machine = TriggerMachine()
        let commandes = machine.traite(.appui(0)) + machine.traite(.relachement(Self.court))

        #expect(!commandes.contains(.demarrer))
        #expect(!commandes.contains(.terminer))
    }

    @Test("Deux appuis trop espacés ne verrouillent pas")
    func doubleAppuiTropLent() {
        var machine = TriggerMachine()
        _ = machine.traite(.appui(0))
        _ = machine.traite(.relachement(Self.court))

        // Second appui au-delà du seuil : c'est un nouveau geste, pas un double.
        let commandes = machine.traite(.appui(Self.court + Self.long))
        #expect(commandes == [.armerMinuterie(Self.seuil)])
        #expect(machine.etat == .repos)

        // Et il se qualifie normalement en maintien.
        #expect(machine.traite(.minuterie(Self.court + Self.long + Self.seuil)) == [.demarrer])
        #expect(machine.etat == .ecoute)
    }

    // MARK: - Robustesse

    @Test("Les événements orphelins sont sans effet")
    func evenementsOrphelins() {
        var machine = TriggerMachine()

        #expect(machine.traite(.relachement(0)).isEmpty)
        #expect(machine.traite(.minuterie(1)).isEmpty)
        #expect(machine.traite(.echap(2)).isEmpty)
        #expect(machine.etat == .repos)
    }

    /// Le geste doit rester enchaînable : deux dictées de suite sans état
    /// résiduel entre les deux.
    @Test("Deux maintiens successifs se comportent à l'identique")
    func maintiensEnchaines() {
        var machine = TriggerMachine()

        for depart in [0.0, 10.0] {
            _ = machine.traite(.appui(depart))
            #expect(machine.traite(.minuterie(depart + Self.seuil)) == [.demarrer])
            #expect(machine.traite(.relachement(depart + 2)) == [.terminer])
            #expect(machine.etat == .repos)
        }
    }

    // MARK: - États affichés

    @Test("Aucun état visible tant que le geste n'est pas qualifié")
    func pasDeClignotement() {
        var machine = TriggerMachine()
        _ = machine.traite(.appui(0))

        // Sous le seuil, rien ne s'affiche : un overlay qui apparaîtrait à
        // chaque effleurement de la touche clignoterait.
        #expect(machine.etat == .repos)
        #expect(machine.etat.estVisible == false)
    }

    @Test("Les deux écoutes partagent le même HUD")
    func memeHUDPourLesDeuxEcoutes() {
        #expect(DictationState.ecoute.signal == DictationState.ecouteVerrouillee.signal)
    }

    @Test("Le traitement reste distinct des écoutes")
    func traitementDistinct() {
        // La bande suit le micro pendant l'écoute et ne le suit plus pendant
        // la transcription : sans ça, elle resterait figée sur la dernière
        // mesure et laisserait croire que l'app est bloquée.
        #expect(DictationState.traitement.signal != DictationState.ecoute.signal)
        #expect(DictationState.traitement.signal == .travaille)
        #expect(DictationState.repos.signal == .eteint)
        #expect(DictationState.repos.estVisible == false)
    }

    /// Ce qui sépare désormais les deux gestes à l'écran n'est plus la forme
    /// mais la durée : le HUD du maintien s'efface au relâchement, celui du
    /// double-appui tient jusqu'à ce qu'on referme.
    @Test("Le maintien efface le HUD au relâchement")
    func hudDuMaintienSEfface() {
        var machine = TriggerMachine()
        _ = machine.traite(.appui(0))
        _ = machine.traite(.minuterie(Self.seuil))
        #expect(machine.etat.estVisible)

        _ = machine.traite(.relachement(2))
        #expect(machine.etat.estVisible == false)
    }

    @Test("Le double-appui garde le glyphe jusqu'à la fermeture")
    func glypheDuVerrouillagePersiste() {
        var machine = TriggerMachine()
        _ = machine.traite(.appui(0))
        _ = machine.traite(.relachement(Self.court))
        _ = machine.traite(.appui(Self.court * 2))
        #expect(machine.etat.estVisible)

        // Ni le relâchement de la touche…
        _ = machine.traite(.relachement(Self.court * 3))
        #expect(machine.etat.estVisible)
        // …ni le temps qui passe ne l'effacent.
        _ = machine.traite(.minuterie(30))
        #expect(machine.etat.estVisible)

        // Seul un nouvel appui referme.
        _ = machine.traite(.appui(60))
        #expect(machine.etat.estVisible == false)
    }
}
