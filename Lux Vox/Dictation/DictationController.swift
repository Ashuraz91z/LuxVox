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

    /// La touche 🌐 est libre : macOS ne lui attache plus rien.
    ///
    /// Lu dans le système, jamais déclaré par l'utilisateur — voir
    /// `ReglageDuGlobe`. C'est la première cause d'échec prévisible du produit
    /// (cahier §6, décision *b*), et une étape cochée sur parole l'aurait
    /// laissée passer.
    private(set) var toucheReglee: Bool
    /// Ce que macOS attache à la touche, pour le dire dans la bulle. `nil`
    /// quand la clé est absente : le réglage vaut alors son défaut système.
    private(set) var usageDuGlobe: ReglageDuGlobe?
    /// L'écriture du réglage a échoué. Il reste le panneau Clavier.
    private(set) var liberationRefusee = false
    /// La touche vient d'être reprise à macOS, et la bulle doit le montrer.
    ///
    /// Sans cet état, l'app changeait un réglage du clavier et passait à la
    /// bulle suivante sans rien dire. Pour le micro et l'Accessibilité,
    /// l'alerte système fait cette preuve à notre place ; ici personne ne la
    /// fait, et un changement invisible est un changement auquel on ne croit
    /// pas.
    private(set) var toucheVientDEtreLiberee = false
    /// Ce qui a fait échouer le dernier téléchargement du modèle. Distinct de
    /// `dernierIncident`, qui porte les pannes de dictée : les deux
    /// s'affichent à des endroits différents et ne s'effacent pas ensemble.
    private(set) var incidentModele: String?
    /// Le modèle vient d'arriver, mais le moteur ne le chargera qu'au
    /// prochain lancement — voir `installeModele()`.
    private(set) var redemarrageRequis = false

    /// La bulle affichée par le voile.
    private(set) var etapeMiseEnRoute: EtapeMiseEnRoute = .presentation
    /// Les étapes de cette visite-ci, arrêtées à son ouverture.
    ///
    /// Figées, et non recalculées à chaque image : elles servent aussi de
    /// jalons dans la bulle, et une rangée de points qui rétrécit sous l'œil à
    /// mesure qu'on avance est une nuisance de plus à regarder.
    private(set) var etapesDuTour: [EtapeMiseEnRoute] = []
    /// L'étape dont on attend le dénouement pendant que l'utilisateur a la
    /// main ailleurs — Réglages Système, ou téléchargement. Le voile est
    /// effacé tant qu'elle vaut quelque chose.
    private var attente: EtapeMiseEnRoute?
    /// Où se trouve la marque dans la barre des menus, en coordonnées d'écran.
    ///
    /// Relevé plutôt que lu en plein rendu : la barre se réorganise dès qu'une
    /// autre app y pose ou retire un élément, et le trou du voile doit suivre.
    private(set) var cadreIcone: CGRect = .zero

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

    /// Vrai quand il n'y a plus rien à faire pour dicter. C'est ce qui décide
    /// si le voile de mise en route s'ouvre au lancement.
    var miseEnRouteComplete: Bool {
        microAccorde
            && accessibiliteAccordee
            && etatModele.estPret
            && (declencheur != .globe || toucheReglee)
    }

    private static let clefDeclencheur = "declencheur"

    /// Les tests d'interface lancent l'app pour de vrai, et le voile prend
    /// l'écran entier. Un test qui confisque l'écran de qui le lance est un
    /// test qu'on n'ose plus lancer — celui-ci laissait en plus derrière lui un
    /// panneau que le harnais n'arrivait pas à fermer, et une minute de
    /// délai d'attente. L'argument le désarme, et rien d'autre :
    /// `app.launchArguments = ["-sansMiseEnRoute", "YES"]`.
    private static var miseEnRouteDesarmee: Bool {
        UserDefaults.standard.bool(forKey: "sansMiseEnRoute")
    }

    private let journal = Logger(subsystem: "lux-audere.Lux-Vox", category: "dictee")
    private let trigger = KeyboardTrigger()
    private let overlay = OverlayController()
    private let voile = VoileController()
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
        toucheReglee = ReglageDuGlobe.estLibre
        usageDuGlobe = ReglageDuGlobe.actuel

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

    /// Au premier démarrage, on demande le micro puis on ouvre la fenêtre de
    /// mise en route s'il reste quoi que ce soit à régler.
    ///
    /// Le modèle y est **proposé**, pas téléchargé en douce : l'app vend le
    /// fait que rien ne sort de la machine, et déclencher plusieurs centaines
    /// de mégaoctets sans prévenir — potentiellement en partage de connexion —
    /// contredirait ce contrat au seul moment où l'utilisateur décide s'il
    /// fait confiance.
    private func prepareLaPremiereFois() async {
        if !AudioCapture.permissionAccordee && !AudioCapture.permissionRefusee {
            await AudioCapture.demandePermission()
            rafraichitPermissions()
        }

        await rafraichitModele()

        if !miseEnRouteComplete, !Self.miseEnRouteDesarmee {
            ouvreMiseEnRoute()
            // Sans modèle il n'y a rien à préchauffer, et la fenêtre s'en
            // charge quand l'utilisateur aura cliqué.
            guard etatModele.estPret else { return }
        }

        // Préchauffage hors du chemin de la première dictée : c'est ici que
        // CoreML compile le modèle pour le Neural Engine.
        await prechauffeMoteur()
    }

    func rafraichitModele() async {
        etatModele = WhisperKitMoteur.etat()
    }

    /// Télécharge le modèle. Le préchauffage, lui, attend le prochain
    /// lancement.
    func installeModele() async {
        // Plusieurs minutes de téléchargement ne se regardent pas sous un
        // écran assombri. L'assombrissement se retire, la bulle reste et porte
        // la progression ; le voile entier ne revient qu'à la fin, pour
        // demander le redémarrage.
        confie(.modele)

        incidentModele = nil
        etatModele = .installation(0)

        do {
            try await WhisperKitMoteur.installe { [weak self] avancement in
                Task { @MainActor in
                    self?.etatModele = .installation(avancement)
                }
            }
        } catch {
            await rafraichitModele()
            let raison = "Le téléchargement n'a pas abouti : \(error.localizedDescription)"
            incidentModele = raison
            journal.error("\(raison, privacy: .public)")
            return
        }

        await rafraichitModele()

        // On ne charge pas le moteur dans la foulée : le premier chargement
        // juste après un téléchargement laissait l'app figée sur l'écran de
        // préparation, sans moyen de savoir s'il avançait. Un redémarrage règle
        // le problème, et la bulle suivante le demande explicitement.
        redemarrageRequis = true
    }

    // MARK: - Mise en route

    /// Ouvre le voile sur une visite neuve.
    func ouvreMiseEnRoute() {
        rafraichitLaTouche()
        toucheVientDEtreLiberee = false
        liberationRefusee = false
        etapesDuTour = EtapeMiseEnRoute.visite(aRegler: aBesoin)
        montre(.presentation)
    }

    func fermeMiseEnRoute() {
        attente = nil
        voile.ferme()
    }

    func avanceMiseEnRoute() {
        montre(EtapeMiseEnRoute.apres(etapeMiseEnRoute, dans: etapesDuTour, aRegler: aBesoin))
    }

    /// Reprend la touche 🌐 à macOS, sans quitter la bulle.
    ///
    /// C'est la seule étape que l'app puisse franchir à la place de
    /// l'utilisateur : les deux permissions demandent une alerte système par
    /// construction, le modèle demande le réseau — celle-ci n'est qu'une
    /// préférence, et la laisser à faire à la main était le point où l'on
    /// perdait les gens.
    func libereLaTouche() {
        liberationRefusee = !ReglageDuGlobe.libere()
        rafraichitLaTouche()
        // On ne passe pas à la suite : la bulle reste pour dire ce qui vient
        // d'être fait, et c'est l'utilisateur qui enchaîne.
        toucheVientDEtreLiberee = toucheReglee
    }

    /// L'autre sortie : changer de touche plutôt que de réglage.
    ///
    /// Le Ctrl droit n'est réservé par personne (cahier §6, décision *b*) —
    /// rien à écrire dans le système, et l'étape n'a plus lieu d'être.
    func basculeVersCtrlDroit() {
        declencheur = .ctrlDroit
        if etapeMiseEnRoute == .touche { avanceMiseEnRoute() }
    }

    /// Relit le réglage de la touche dans le système.
    ///
    /// **Volontairement hors de `rafraichitPermissions`**, qui tourne chaque
    /// seconde : lire une préférence d'un autre domaine force un aller-retour
    /// synchrone avec `cfprefsd`, et ce thread est aussi celui qui sert le
    /// rappel du tap clavier. macOS désarme un tap trop lent — le code prévoit
    /// déjà de le réarmer, mais autant ne pas provoquer la panne. On ne relit
    /// donc que lorsqu'on attend précisément ce réglage.
    private func rafraichitLaTouche() {
        toucheReglee = ReglageDuGlobe.estLibre
        usageDuGlobe = ReglageDuGlobe.actuel
    }

    // MARK: Les allers-retours hors de l'app

    func demandeMicroPuisAttend() {
        confie(.micro)
        Task { await demandeMicro() }
    }

    func ouvreReglagesMicroPuisAttend() {
        confie(.micro)
        ouvreReglagesMicro()
    }

    func demandeAccessibilitePuisAttend() {
        confie(.accessibilite)
        demandeAccessibilite()
    }

    func ouvreReglagesAccessibilitePuisAttend() {
        confie(.accessibilite)
        ouvreReglagesAccessibilite()
    }

    /// Seule étape que rien ne vient dénouer : le voile ne reviendra pas de
    /// lui-même, et la bulle reste donc à l'écran avec son « C'est fait ».
    func ouvreReglagesClavierPuisAttend() {
        confie(.touche)
        ouvreReglagesClavier()
    }

    /// Ce qu'il reste à demander, étape par étape.
    private func aBesoin(_ etape: EtapeMiseEnRoute) -> Bool {
        switch etape {
        case .presentation, .geste: true
        case .micro: !microAccorde
        case .accessibilite: !accessibiliteAccordee
        case .touche: declencheur == .globe && !toucheReglee
        case .modele: !etatModele.estPret
        case .redemarrage: redemarrageRequis
        }
    }

    private func montre(_ etape: EtapeMiseEnRoute) {
        attente = nil
        pose(etape, .pleinEcran)
    }

    /// Rien ne se pose avant que l'icône soit située : c'est elle qui donne sa
    /// place au trou comme à la bulle.
    private func pose(_ etape: EtapeMiseEnRoute, _ etendue: EtendueDuVoile) {
        etapeMiseEnRoute = etape
        surveille()
        Task {
            await situeLIcone()
            voile.montre(self, etendue)
        }
    }

    /// `MenuBarExtra` pose son icône *après* le lancement : juste après
    /// `applicationDidFinishLaunching`, sa fenêtre existe déjà mais son cadre
    /// vaut encore zéro. Ouvrir le voile à cet instant reviendrait à cercler
    /// du vide, donc on l'attend — brièvement, et on s'en passe plutôt que de
    /// faire attendre indéfiniment devant un écran noir.
    private func situeLIcone() async {
        guard cadreIcone == .zero else { return }
        for _ in 0..<40 {
            if let cadre = VoileController.cadreDeLIcone() {
                cadreIcone = cadre
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Rend l'écran et note ce qu'on attend.
    ///
    /// L'assombrissement se retire, la bulle reste : envoyer quelqu'un dans
    /// les Réglages Système et assombrir la fenêtre qu'on vient de lui faire
    /// ouvrir serait absurde, et la faire disparaître emporterait le bouton
    /// dont il a besoin en revenant. La veille rappellera le voile entier dès
    /// que l'étape sera franchie.
    private func confie(_ etape: EtapeMiseEnRoute) {
        attente = etape
        pose(etape, .bulleSeule)
    }

    /// Le voile revient dès que ce qu'on attendait est arrivé.
    ///
    /// Le modèle est le seul cas où l'échec compte autant que la réussite :
    /// un téléchargement qui n'aboutit pas doit se dire, sinon l'utilisateur
    /// attend devant une app qui ne fera jamais rien.
    private func reprendSiLaMainRevient() {
        guard let etape = attente else { return }
        // Le seul moment où le réglage de la touche peut changer sous nos
        // pieds : l'utilisateur est dans le panneau Clavier.
        if etape == .touche { rafraichitLaTouche() }

        let franchie = switch etape {
        case .modele: etatModele.estPret || incidentModele != nil
        default: !aBesoin(etape)
        }
        guard franchie else { return }

        attente = nil
        if redemarrageRequis {
            montre(.redemarrage)
        } else if etape == .modele, incidentModele != nil {
            montre(.modele)
        } else {
            etapeMiseEnRoute = etape
            avanceMiseEnRoute()
        }
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
    ///
    /// Elle tourne tant qu'il y a une raison de regarder : le déclencheur à
    /// armer dès que l'Accessibilité arrive, et la mise en route qui doit
    /// avancer seule pendant l'aller-retour dans les Réglages Système. Rien
    /// dans le système ne prévient l'app qu'une permission vient d'être
    /// accordée dans un autre processus.
    private func surveille() {
        guard surveillance == nil else { return }
        surveillance = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }

                rafraichitPermissions()
                if accessibiliteAccordee { trigger.demarre() }
                if voile.estVisible, let cadre = VoileController.cadreDeLIcone() {
                    cadreIcone = cadre
                }
                reprendSiLaMainRevient()

                if accessibiliteAccordee && attente == nil && !voile.estVisible { break }
            }
            self?.surveillance = nil
        }
    }

    private func ouvre(_ adresse: String) {
        guard let url = URL(string: adresse) else { return }
        NSWorkspace.shared.open(url)
    }
}
