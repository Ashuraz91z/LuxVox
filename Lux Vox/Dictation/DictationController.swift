//
//  DictationController.swift
//  Lux Vox
//

import AppKit
import Observation
import os

/// Relie le déclencheur clavier au micro, au moteur et à ce qui se voit.
///
/// L'injection n'existe pas encore : le texte transcrit est nettoyé (passe 1)
/// puis rangé dans `dernierTexte`, d'où le panneau déroulant le montre.
@MainActor
@Observable
final class DictationController {

    private(set) var etat: DictationState = .repos
    private(set) var accessibiliteAccordee = KeyboardTrigger.accessibiliteAccordee
    private(set) var microAccorde = AudioCapture.permissionAccordee
    private(set) var etatModele: EtatModele = .aInstaller
    /// Le modèle est chargé et prêt à transcrire.
    ///
    /// Distinct de `etatModele` : les fichiers peuvent être présents dans le
    /// paquet alors que CoreML n'a pas fini de les compiler pour le Neural
    /// Engine. Ce premier chargement dure près d'une minute et demie, et il
    /// n'a lieu qu'une fois par version installée.
    private(set) var moteurPret = false

    /// Dernière transcription, nettoyée. Filet de sécurité tant qu'on n'injecte
    /// rien.
    private(set) var dernierTexte = ""
    /// Ce qui a empêché la dernière dictée d'aboutir. Avaler les erreurs rend
    /// une panne indiagnosticable — pour l'utilisateur comme pour le
    /// développeur.
    private(set) var dernierIncident: String?
    /// Temps entre la fin du geste et le texte prêt — le chiffre que l'étape 2
    /// doit produire.
    private(set) var derniereLatence: Duration?

    var declencheur: KeyboardTrigger.Declencheur {
        didSet {
            trigger.declencheur = declencheur
            UserDefaults.standard.set(declencheur.rawValue, forKey: Self.clefDeclencheur)
        }
    }

    private static let clefDeclencheur = "declencheur"

    private let journal = Logger(subsystem: "lux-audere.Lux-Vox", category: "dictee")
    private let trigger = KeyboardTrigger()
    private let overlay = OverlayController()
    private let installation = InstallationController()
    private let capture = AudioCapture()
    private let injecteur = TextInjector()
    /// WhisperKit, avec son modèle embarqué : c'est lui qui transcrit.
    ///
    /// `SpeechTranscriberMoteur` reste dans le projet derrière le même
    /// protocole — la décision *a* du cahier voulait précisément que le choix
    /// reste réversible sans toucher au reste de l'app.
    private let moteur: any MoteurTranscription = WhisperKitMoteur()

    /// L'ouverture est asynchrone et le relâchement peut la précéder : on
    /// garde la tâche pour l'attendre au lieu de trouver `session` à `nil` et
    /// de perdre la dictée. C'était la cause d'un silence complet sur les
    /// dictées courtes.
    private var ouverture: Task<(any SessionTranscription)?, Never>?
    /// L'application visée, relevée au début du geste : c'est à elle que le
    /// texte est destiné, pas à celle qui aura le focus deux secondes plus tard.
    private var cible: pid_t?
    private var surveillance: Task<Void, Never>?

    init() {
        let enregistre = UserDefaults.standard.string(forKey: Self.clefDeclencheur)
        declencheur = enregistre.flatMap(KeyboardTrigger.Declencheur.init(rawValue:)) ?? .globe

        trigger.declencheur = declencheur
        trigger.onCommande = { [weak self] commande in
            self?.applique(commande)
        }
    }

    // MARK: - Démarrage

    func demarre() {
        rafraichitPermissions()
        if accessibiliteAccordee {
            trigger.demarre()
        } else {
            surveille()
        }

        Task { await prepareLaPremiereFois() }
    }

    /// Au premier démarrage, on demande le micro puis on **propose** le
    /// téléchargement du modèle.
    ///
    /// Proposer, pas télécharger en douce : l'app vend le fait que rien ne sort
    /// de la machine, et déclencher plusieurs dizaines de mégaoctets sans
    /// prévenir — potentiellement en partage de connexion — contredirait ce
    /// contrat au seul moment où l'utilisateur décide s'il fait confiance.
    private func prepareLaPremiereFois() async {
        if !AudioCapture.permissionAccordee && !AudioCapture.permissionRefusee {
            await AudioCapture.demandePermission()
            rafraichitPermissions()
        }

        await rafraichitModele()

        if etatModele == .aInstaller {
            // Proposer, pas télécharger en douce : l'app vend le fait que rien
            // ne sort de la machine, et lancer 143 Mo sans prévenir —
            // potentiellement en partage de connexion — contredirait ce contrat
            // au seul moment où l'utilisateur décide s'il fait confiance.
            guard proposeInstallation() else {
                // Sans modèle, il n'y a pas de dictée : rester ouvert
                // laisserait une icône inerte dans la barre des menus.
                NSApp.terminate(nil)
                return
            }
            await installeModele()
            return
        }

        // Préchauffage hors du chemin de la première dictée : c'est ici que
        // CoreML compile le modèle pour le Neural Engine.
        await prechauffeMoteur()
    }

    /// Alerte système native, comme pour les permissions (DA §9) : c'est le
    /// seul langage que l'utilisateur croit à ce moment-là.
    private func proposeInstallation() -> Bool {
        let alerte = NSAlert()
        alerte.messageText = "Télécharger le modèle de transcription ?"
        alerte.informativeText = """
        Lux Vox a besoin d'un modèle de reconnaissance vocale d'environ 650 Mo, \
        téléchargé une seule fois. Ensuite, la dictée fonctionne entièrement \
        hors ligne : plus rien ne sort de cette machine.
        """
        alerte.alertStyle = .informational
        alerte.addButton(withTitle: "Télécharger")
        alerte.addButton(withTitle: "Quitter Lux Vox")
        NSApp.activate(ignoringOtherApps: true)
        return alerte.runModal() == .alertFirstButtonReturn
    }

    func rafraichitModele() async {
        etatModele = WhisperKitMoteur.etat()
    }

    /// Télécharge le modèle, puis le préchauffe dans la foulée.
    func installeModele() async {
        etatModele = .installation(0)
        installation.montre(.telechargement(0))

        do {
            try await WhisperKitMoteur.installe { [weak self] avancement in
                Task { @MainActor in
                    self?.etatModele = .installation(avancement)
                    self?.installation.montre(.telechargement(avancement))
                }
            }
        } catch {
            await rafraichitModele()
            let raison = "Le téléchargement n'a pas abouti : \(error.localizedDescription)"
            installation.montre(.echec(raison))
            signale(raison)
            return
        }

        await rafraichitModele()

        // On ne charge pas le moteur dans la foulée : le premier chargement
        // juste après un téléchargement laissait l'app figée sur l'écran de
        // préparation, sans moyen de savoir s'il avançait. Un redémarrage règle
        // le problème, et la fenêtre le demande explicitement.
        installation.montre(.terminee)
    }

    private func prechauffeMoteur() async {
        guard etatModele.estPret, !moteurPret else { return }
        do {
            try await moteur.prechauffe()
            moteurPret = true
        } catch {
            signale("Le moteur n'a pas pu charger le modèle.")
        }
    }

    // MARK: - Le geste

    private func applique(_ commande: TriggerCommand) {
        switch commande {
        case .demarrer:
            montre(.ecoute)
            dernierIncident = nil
            cible = injecteur.cibleActuelle()
            ouverture = Task { await ouvreLaSession() }
        case .verrouiller:
            montre(.ecouteVerrouillee)
        case .terminer:
            Task { await conclut() }
        case .annuler:
            Task { await abandonne() }
        case .armerMinuterie, .desarmerMinuterie:
            break
        }
    }

    private func ouvreLaSession() async -> (any SessionTranscription)? {
        rafraichitPermissions()

        guard microAccorde else {
            signale("Permission micro non accordée.")
            montre(.repos)
            return nil
        }
        if !etatModele.estPret {
            // L'état affiché peut dater du lancement : on revérifie avant de
            // refuser une dictée, plutôt que de se fier à un cache périmé.
            await rafraichitModele()
        }
        guard etatModele.estPret else {
            signale("Modèle non installé — téléchargez-le depuis le menu.")
            montre(.repos)
            return nil
        }
        guard moteurPret else {
            signale("Le moteur finit de se préparer — réessayez dans un instant.")
            montre(.repos)
            return nil
        }

        do {
            let session = try await moteur.ouvreSession()
            try capture.demarre(
                recevoir: { tampon in
                    Task { await session.pousse(tampon) }
                },
                niveaux: { [weak self] mesures in
                    Task { @MainActor in self?.overlay.mesure(mesures) }
                }
            )
            journal.info("session ouverte")
            return session
        } catch {
            signale("Ouverture impossible : \(error.localizedDescription)")
            capture.arrete()
            montre(.repos)
            return nil
        }
    }

    private func conclut() async {
        // On attend l'ouverture plutôt que de conclure sur une session absente.
        let session = await ouverture?.value
        ouverture = nil

        guard let session else {
            montre(.repos)
            return
        }

        montre(.traitement)
        capture.arrete()

        let depart = ContinuousClock.now
        defer { montre(.repos) }

        do {
            let brut = try await session.termine()
            derniereLatence = ContinuousClock.now - depart
            journal.info("brut reçu : \(brut.count, privacy: .public) caractères")

            guard !brut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                signale("Rien n'a été entendu.")
                return
            }

            let propre = TextCleaner.clean(brut)
            guard !propre.isEmpty else {
                signale("Le nettoyage n'a rien laissé du texte entendu.")
                return
            }

            // L'historique d'abord : il doit contenir le texte même quand
            // l'injection est refusée, c'est le filet de sécurité.
            dernierTexte = propre
            dernierIncident = nil

            switch await injecteur.injecte(propre, vers: cible) {
            case .injecte:
                break
            case .refuse(let refus):
                signale(refus.explication)
            }
        } catch {
            signale("Transcription interrompue : \(error.localizedDescription)")
        }
    }

    private func abandonne() async {
        let session = await ouverture?.value
        ouverture = nil
        capture.arrete()
        montre(.repos)
        await session?.annule()
    }

    private func signale(_ raison: String) {
        journal.error("\(raison, privacy: .public)")
        dernierIncident = raison
    }

    // MARK: - Permissions

    func demandeAccessibilite() {
        KeyboardTrigger.demandeAccessibilite()
        surveille()
    }

    func demandeMicro() async {
        await AudioCapture.demandePermission()
        rafraichitPermissions()
    }

    func ouvreReglagesAccessibilite() {
        ouvre("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func ouvreReglagesMicro() {
        ouvre("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    /// C'est là que se règle « Appuyer sur 🌐 pour » sur « Ne rien faire » —
    /// première cause d'échec prévisible, et elle n'a rien à voir avec le code.
    func ouvreReglagesClavier() {
        ouvre("x-apple.systempreferences:com.apple.preference.keyboard")
    }

    // MARK: - Interne

    private func montre(_ nouveau: DictationState) {
        etat = nouveau
        overlay.affiche(nouveau)
    }

    private func rafraichitPermissions() {
        accessibiliteAccordee = KeyboardTrigger.accessibiliteAccordee
        microAccorde = AudioCapture.permissionAccordee
    }

    /// Une `Task` plutôt qu'un `Timer` : le minuteur se passe en paramètre du
    /// rappel, ce qui le ferait traverser une frontière d'isolation alors qu'il
    /// n'est pas `Sendable`.
    private func surveille() {
        guard surveillance == nil else { return }
        surveillance = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self else { return }
                rafraichitPermissions()
                guard accessibiliteAccordee else { continue }
                trigger.demarre()
                surveillance = nil
                return
            }
        }
    }

    private func ouvre(_ adresse: String) {
        guard let url = URL(string: adresse) else { return }
        NSWorkspace.shared.open(url)
    }
}
