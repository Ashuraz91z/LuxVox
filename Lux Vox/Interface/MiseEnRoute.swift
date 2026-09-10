//
//  MiseEnRoute.swift
//  Lux Vox
//

import AppKit
import SwiftUI

// MARK: - Les étapes

/// Ce que la mise en route a à dire, dans l'ordre où elle le dit.
///
/// Une étape par bulle. Celles du milieu ne paraissent que si elles ont
/// quelque chose à demander — voir `DictationController.aBesoin(_:)` — donc un
/// utilisateur déjà en règle ne voit que la présentation et le geste.
nonisolated enum EtapeMiseEnRoute: String, CaseIterable, Identifiable, Sendable {
    /// Là où l'app vit. La seule étape qui ne demande rien.
    case presentation
    case micro
    case accessibilite
    case touche
    case modele
    case redemarrage
    /// Comment on dicte. La seule chose que cette visite apprend vraiment.
    case geste

    var id: String { rawValue }

    /// En capitales, comme les rubriques du panneau déroulant (DA §6). La
    /// présentation n'en a pas : elle porte la marque à la place.
    var rubrique: String? {
        switch self {
        case .presentation: nil
        case .micro: "MICROPHONE"
        case .accessibilite: "ACCESSIBILITÉ"
        case .touche: "TOUCHE 🌐"
        case .modele: "MODÈLE FRANÇAIS"
        case .redemarrage: "MODÈLE INSTALLÉ"
        case .geste: "C'EST PRÊT"
        }
    }

    /// Les deux étapes qui ne demandent rien : l'app se présente, puis dit
    /// comment on dicte. Elles se montrent quelle que soit la machine.
    var seMontreToujours: Bool { self == .presentation || self == .geste }

    /// Les étapes de cette visite-ci, arrêtées à son ouverture.
    ///
    /// `aRegler` dit, pour une étape, s'il lui reste quelque chose à demander.
    /// Le passer en paramètre plutôt que de lire l'état du système isole
    /// l'enchaînement — même raison que pour `TriggerMachine` : il se vérifie
    /// alors sans permission, sans barre des menus et sans écran.
    static func visite(aRegler: (EtapeMiseEnRoute) -> Bool) -> [EtapeMiseEnRoute] {
        allCases.filter { $0.seMontreToujours || aRegler($0) }
    }

    /// L'étape suivante de la visite qui ait encore quelque chose à demander.
    ///
    /// Une étape réglée entre-temps est sautée — accorder le micro depuis les
    /// Réglages Système pendant qu'on en est à l'Accessibilité ne doit pas
    /// faire réapparaître une bulle qui n'a plus rien à dire. Elle garde son
    /// point dans les jalons : ce qui a été promis reste compté.
    static func apres(
        _ courante: EtapeMiseEnRoute,
        dans visite: [EtapeMiseEnRoute],
        aRegler: (EtapeMiseEnRoute) -> Bool
    ) -> EtapeMiseEnRoute {
        visite.drop { $0 != courante }
            .dropFirst()
            .first { $0.seMontreToujours || aRegler($0) } ?? .geste
    }
}

// MARK: - Le voile

/// Les deux façons dont la mise en route occupe l'écran.
nonisolated enum EtendueDuVoile: Equatable, Sendable {
    /// Tout s'assombrit, l'icône seule reste allumée. On demande l'attention.
    case pleinEcran
    /// La bulle seule, posée sous l'icône. L'utilisateur a la main ailleurs —
    /// dans les Réglages Système, ou devant un téléchargement — et l'écran ne
    /// nous appartient plus.
    case bulleSeule
}

/// L'écran s'assombrit, l'icône reste allumée, une bulle s'y accroche.
///
/// **Révision de la DA §9.** Le §9 décrivait « une fenêtre d'accueil sobre
/// listant les trois permissions ». Ce n'en est plus une, et la raison tient
/// au produit : Lux Vox n'a pas de fenêtre, il a une marque de 16 points dans
/// la barre des menus. Une page qui explique où regarder est moins claire que
/// le fait d'éteindre tout le reste et de laisser la marque allumée.
///
/// Ce que §9 demandait vraiment est tenu : une seule surface dessinée, l'état
/// de chaque prérequis, un bouton par prérequis qui ouvre le bon panneau des
/// Réglages Système, et aucune réouverture spontanée une fois tout accordé.
/// Les demandes elles-mêmes passent toujours par les alertes natives — le
/// voile ne réclame aucun pouvoir, il montre où regarder.
///
/// **L'assombrissement se retire dès qu'on cesse de demander.** Envoyer
/// quelqu'un dans les Réglages Système et l'y suivre en assombrissant la
/// fenêtre qu'on vient de lui faire ouvrir n'a pas de sens : le panneau passe
/// alors en `bulleSeule`, l'écran est rendu, et la bulle reste posée sous
/// l'icône avec ce qu'il faut pour reprendre.
@MainActor
final class VoileController {

    private var panneau: NSPanel?
    /// Gardé pour pouvoir changer d'étendue et mesurer la bulle.
    private var hote: NSHostingView<VoileMiseEnRoute>?

    var estVisible: Bool { panneau?.isVisible == true }

    func montre(_ controleur: DictationController, _ etendue: EtendueDuVoile) {
        guard let ecran = ecranDe(controleur.cadreIcone) else { return }

        let panneau = panneauExistantOuNouveau(controleur)
        hote?.rootView = VoileMiseEnRoute(controleur: controleur, etendue: etendue)

        switch etendue {
        case .pleinEcran:
            panneau.setFrame(ecran.frame, display: true)
            // Ne réactiver qu'à l'ouverture : chaque étape rappelle cette
            // méthode, et reprendre le focus à chaque bulle serait du vol.
            guard !panneau.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            panneau.makeKeyAndOrderFront(nil)

        case .bulleSeule:
            panneau.setFrame(cadreDeLaBulle(controleur.cadreIcone, ecran), display: true)
            // Ni activation ni focus : l'utilisateur est en train de régler
            // quelque chose ailleurs, et lui prendre le clavier au milieu
            // serait exactement ce qu'on cherche à éviter. Les boutons de la
            // bulle répondent quand même — un clic n'a pas besoin de la
            // fenêtre clef.
            panneau.orderFrontRegardless()
        }
    }

    func ferme() {
        panneau?.orderOut(nil)
    }

    /// Le panneau réduit à la bulle et à son fil, mesuré sur son contenu.
    ///
    /// Le mesurer plutôt que lui donner une hauteur généreuse : tout ce que le
    /// panneau couvre, il l'intercepte. Trois cents points de vide sous la
    /// bulle avaleraient les clics dans un coin de l'écran où l'utilisateur
    /// n'a aucune raison de se douter qu'il y a quelque chose.
    private func cadreDeLaBulle(_ icone: CGRect, _ ecran: NSScreen) -> NSRect {
        hote?.layoutSubtreeIfNeeded()
        let hauteur = hote?.fittingSize.height ?? 200
        return NSRect(
            x: ecran.frame.minX + Self.abscisseDeLaBulle(icone: icone, ecran: ecran.frame),
            y: icone.minY - hauteur,
            width: VoileMiseEnRoute.largeurBulle,
            height: hauteur
        )
    }

    /// La bulle se centre sous l'icône, sans jamais sortir de l'écran.
    ///
    /// Partagé par les deux étendues : la bulle ne doit pas glisser
    /// latéralement quand l'assombrissement se retire.
    static func abscisseDeLaBulle(icone: CGRect, ecran: CGRect) -> CGFloat {
        let ideal = icone.midX - ecran.minX - VoileMiseEnRoute.largeurBulle / 2
        return min(max(16, ideal), ecran.width - VoileMiseEnRoute.largeurBulle - 16)
    }

    /// Le cadre de l'icône dans la barre des menus, en coordonnées d'écran.
    ///
    /// `MenuBarExtra` ne donne pas accès à son `NSStatusItem`, et sans lui il
    /// n'y a rien à éclairer. On reconnaît sa fenêtre à ce qu'elle est : une
    /// fenêtre de l'app, au niveau de la barre de statut, étroite, et posée
    /// tout en haut d'un écran. Le HUD de dictée partage ce niveau — c'est la
    /// dernière condition qui l'écarte, lui vit en bas.
    static func cadreDeLIcone() -> CGRect? {
        NSApp.windows.first { fenetre in
            guard fenetre.isVisible, fenetre.level == .statusBar, fenetre.frame.width < 200
            else { return false }
            return NSScreen.screens.contains { $0.frame.maxY - fenetre.frame.maxY < 1 }
        }?.frame
    }

    private func ecranDe(_ icone: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(icone) } ?? NSScreen.main
    }

    private func panneauExistantOuNouveau(_ controleur: DictationController) -> NSPanel {
        if let panneau { return panneau }

        let nouveau = PanneauVoile(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        nouveau.isFloatingPanel = true
        // Le niveau du volet système. `.screenSaver` ne suffit pas : la barre
        // des menus est composée au-dessus de lui et resterait allumée sur
        // toute sa longueur — l'icône ne se détacherait alors de rien.
        nouveau.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        nouveau.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        nouveau.isOpaque = false
        nouveau.backgroundColor = .clear
        nouveau.hasShadow = false
        nouveau.hidesOnDeactivate = false
        nouveau.isReleasedWhenClosed = false
        let hote = NSHostingView(
            rootView: VoileMiseEnRoute(controleur: controleur, etendue: .pleinEcran)
        )
        // Sans cela, SwiftUI creuse la zone sûre de la barre des menus dans la
        // vue et l'assombrissement laisse un liseré clair sur les bords.
        hote.safeAreaRegions = []
        nouveau.contentView = hote

        self.hote = hote
        panneau = nouveau
        return nouveau
    }
}

/// Sans cette surcharge, un panneau sans barre de titre ne devient jamais
/// fenêtre clef — et « Suivant » sur Entrée, « Passer » sur Échap ne
/// répondraient pas.
private final class PanneauVoile: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Ce qui se voit

/// Le voile plein écran : l'assombrissement, le trou sur l'icône, la bulle.
///
/// Tout est en sombre quel que soit le thème du système, pour la même raison
/// que le HUD (voir `LuxColor`) : cet objet flotte au-dessus de n'importe
/// quoi, et le crème de la famille disparaîtrait sur un fond clair.
struct VoileMiseEnRoute: View {
    @Bindable var controleur: DictationController
    let etendue: EtendueDuVoile

    /// Assez large pour trois actions côte à côte sans rogner un libellé —
    /// « Libérer la touche » et « Utiliser Ctrl droit » ne tenaient pas à 300.
    static let largeurBulle: CGFloat = 340
    /// Ce que le trou laisse respirer autour de l'icône.
    private static let jeu: CGFloat = 5
    /// La longueur du fil entre le trou et la bulle.
    static let ecart: CGFloat = 14

    var body: some View {
        switch etendue {
        case .pleinEcran: voile
        case .bulleSeule: bulleSeule
        }
    }

    /// L'écran rendu : il ne reste que le fil et la bulle, à la place exacte
    /// qu'ils occupaient sous le voile. Rien d'autre n'est dessiné, et le
    /// panneau est taillé à cette hauteur — ce qui n'est pas dessiné ici
    /// n'intercepte aucun clic.
    private var bulleSeule: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(LuxColor.accent(.dark).opacity(0.55))
                .frame(width: 1, height: Self.ecart)
                .offset(x: filDansLaBulle)

            Bulle(controleur: controleur)
                .frame(width: Self.largeurBulle)
        }
        .frame(width: Self.largeurBulle)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }

    /// Où le fil tombe dans la bulle. Sans écran de référence — le panneau est
    /// déjà posé au bon endroit — on le recalcule depuis l'icône.
    private var filDansLaBulle: CGFloat {
        let icone = controleur.cadreIcone
        guard let ecran = NSScreen.screens.first(where: { $0.frame.intersects(icone) })
        else { return Self.largeurBulle / 2 }
        let gauche = VoileController.abscisseDeLaBulle(icone: icone, ecran: ecran.frame)
        return icone.midX - ecran.frame.minX - gauche
    }

    private var voile: some View {
        GeometryReader { geo in
            let trou = trouDansLaVue(geo.size)
            let x = bulleX(geo.size, trou)

            ZStack(alignment: .topLeading) {
                assombrissement(geo.size, trou: trou)
                cerne(trou)
                attache(trou)

                Bulle(controleur: controleur)
                    .frame(width: Self.largeurBulle)
                    .offset(x: x, y: trou.maxY + Self.ecart)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Le trou se déplace quand la barre des menus se réorganise :
            // qu'il y glisse plutôt que d'y sauter.
            .animation(.easeOut(duration: 0.18), value: trou)
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }

    // MARK: Géométrie

    /// L'icône, ramenée dans les coordonnées de la vue — l'écran a son origine
    /// en bas à gauche, la vue en haut à gauche.
    private func trouDansLaVue(_ taille: CGSize) -> CGRect {
        let icone = controleur.cadreIcone
        guard let ecran = NSScreen.screens.first(where: { $0.frame.intersects(icone) }) else {
            // Sans icône repérable, la bulle se pose sous le coin haut droit
            // plutôt que de ne rien montrer. Le trou n'a alors rien à cercler :
            // on le réduit à un point.
            return CGRect(x: taille.width - 60, y: 24, width: 0, height: 0)
        }

        return CGRect(
            x: icone.minX - ecran.frame.minX - Self.jeu,
            y: ecran.frame.maxY - icone.maxY - Self.jeu,
            width: icone.width + Self.jeu * 2,
            height: icone.height + Self.jeu * 2
        )
    }

    /// La bulle se centre sous l'icône, sans jamais sortir de l'écran.
    private func bulleX(_ taille: CGSize, _ trou: CGRect) -> CGFloat {
        let ideal = trou.midX - Self.largeurBulle / 2
        return min(max(16, ideal), taille.width - Self.largeurBulle - 16)
    }

    /// Le fil sort du bas du trou et rejoint la bulle.
    private func attache(_ trou: CGRect) -> some View {
        Rectangle()
            .fill(LuxColor.accent(.dark).opacity(0.55))
            .frame(width: 1, height: Self.ecart)
            .offset(x: trou.midX, y: trou.maxY)
    }

    // MARK: Les trois couches

    /// Un rectangle plein écran troué à l'emplacement de l'icône, en règle
    /// pair-impair. Le vrai bouton de la barre des menus se voit au travers,
    /// non assombri : c'est lui qu'on montre, pas une copie dessinée.
    private func assombrissement(_ taille: CGSize, trou: CGRect) -> some View {
        Path { trace in
            // Débordement volontaire : un demi-point d'arrondi entre la vue et
            // la fenêtre laisserait un liseré clair tout autour de l'écran.
            trace.addRect(CGRect(origin: .zero, size: taille).insetBy(dx: -40, dy: -40))
            trace.addRoundedRect(in: trou, cornerSize: CGSize(width: 7, height: 7), style: .continuous)
        }
        .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
    }

    private func cerne(_ trou: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(LuxColor.accent(.dark), lineWidth: 1.5)
            .frame(width: trou.width, height: trou.height)
            .offset(x: trou.minX, y: trou.minY)
    }

}

// MARK: - La bulle

/// Une étape, et rien d'autre : sa rubrique, ce qu'elle demande, ses boutons.
private struct Bulle: View {
    @Bindable var controleur: DictationController

    private var etape: EtapeMiseEnRoute { controleur.etapeMiseEnRoute }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            entete
            propos
            progression
            boutons
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LuxColor.hudFond)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LuxColor.hudTrait.opacity(0.16), lineWidth: 1)
        )
    }

    // MARK: En-tête

    @ViewBuilder
    private var entete: some View {
        if let rubrique {
            HStack(alignment: .firstTextBaseline) {
                Text(rubrique)
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.55)
                    .foregroundStyle(LuxColor.accent(.dark))
                Spacer(minLength: 8)
                jalons
            }
        } else {
            // Le sérif ne paraît qu'ici (DA §6) : le seul moment où l'app se
            // présente par son nom.
            HStack(spacing: 10) {
                MarqueVox(taille: 24)
                Text("Lux Vox")
                    .font(.system(size: 19, design: .serif))
                    .foregroundStyle(LuxColor.text(.dark))
                Spacer(minLength: 8)
                jalons
            }
        }
    }

    /// Où on en est, dans la primitive de la famille (DA §2.1) : des points
    /// pleins, jamais un compteur. Ils se lisent d'un coup d'œil et ne
    /// demandent pas à être lus.
    private var jalons: some View {
        HStack(spacing: 3) {
            ForEach(controleur.etapesDuTour) { jalon in
                Circle()
                    .fill(LuxColor.hudTrait)
                    .frame(width: 3, height: 3)
                    .opacity(jalon == etape ? 1 : 0.28)
            }
        }
    }

    // MARK: Corps

    private var propos: some View {
        Text(texte)
            .font(.system(size: 12.5))
            .foregroundStyle(estEnPeine ? LuxColor.important(.dark) : LuxColor.textSecondary(.dark))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var texte: String {
        switch etape {
        case .presentation:
            "Il vit là-haut, dans la barre des menus. Pas d'icône dans le Dock, pas de fenêtre — cette marque, et c'est tout."
        case .micro:
            "Sans micro, rien à transcrire."
        case .accessibilite:
            "Pour lire la touche de déclenchement, et elle seule."
        case .touche:
            if controleur.toucheVientDEtreLiberee {
                "C'est fait : macOS ne lui attache plus rien. Pressez 🌐 pour vérifier — plus rien ne doit se produire."
            } else if controleur.liberationRefusee {
                "Le réglage n'a pas pu être écrit. Dans Clavier, mettez « Appuyer sur 🌐 pour » sur « Ne rien faire »."
            } else {
                proposDeLaTouche
            }
        case .modele:
            controleur.incidentModele
                ?? "650 Mo, téléchargés une fois. Ensuite tout fonctionne hors ligne — plus rien ne sort de cette machine."
        case .redemarrage:
            "Redémarrez pour terminer. Le moteur se prépare au prochain lancement — comptez une minute, une seule fois."
        case .geste:
            "Maintenez \(controleur.declencheur.libelle), parlez, relâchez. Deux appuis brefs pour dicter sans les mains, Échap pour annuler."
        }
    }

    /// Ce que macOS fait de la touche en ce moment. Le nommer plutôt que dire
    /// « macOS se l'attribue » : c'est ce que l'utilisateur abandonne en
    /// cliquant, et il a le droit de le savoir avant.
    private var proposDeLaTouche: String {
        let attribution =
            if let usage = controleur.usageDuGlobe, usage != .rienFaire {
                "macOS l'attribue à « \(usage.libelle) »."
            } else {
                "macOS se l'attribue déjà."
            }
        // Dire que c'est réversible, et où : on demande à quelqu'un de laisser
        // une app toucher à un réglage de son clavier.
        return "\(attribution) Lux Vox peut la reprendre — réversible dans Réglages Système → Clavier."
    }

    /// La ligne de titre passe au vert de l'accent quand l'étape vient d'être
    /// franchie — le seul cas où une bulle annonce un résultat plutôt qu'une
    /// demande.
    private var rubrique: String? {
        if etape == .touche, controleur.toucheVientDEtreLiberee { return "TOUCHE 🌐 LIBÉRÉE" }
        return etape.rubrique
    }

    private var estEnPeine: Bool {
        if etape == .touche { return controleur.liberationRefusee }
        return etape == .modele && controleur.incidentModele != nil
    }

    @ViewBuilder
    private var progression: some View {
        if etape == .modele, case .installation(let avancement) = controleur.etatModele {
            ProgressView(value: avancement)
                .progressViewStyle(.linear)
                .tint(LuxColor.accent(.dark))
        }
    }

    // MARK: Boutons

    /// Le bouton principal fait avancer ; le second, quand il existe, ouvre le
    /// panneau des Réglages Système. « Passer » reste discret et ferme tout.
    private var boutons: some View {
        HStack(spacing: 8) {
            switch etape {
            case .presentation:
                principal("Commencer") { controleur.avanceMiseEnRoute() }

            case .micro:
                principal("Autoriser") { controleur.demandeMicroPuisAttend() }
                secondaire("Réglages Système") { controleur.ouvreReglagesMicroPuisAttend() }

            case .accessibilite:
                principal("Autoriser") { controleur.demandeAccessibilitePuisAttend() }
                secondaire("Réglages Système") { controleur.ouvreReglagesAccessibilitePuisAttend() }

            case .touche:
                // Deux sorties, aucune qui renvoie chercher un menu déroulant
                // dans un panneau système : reprendre la touche, ou en changer.
                if controleur.toucheVientDEtreLiberee {
                    principal("Suivant") { controleur.avanceMiseEnRoute() }
                } else if controleur.liberationRefusee {
                    principal("Réglages Clavier") { controleur.ouvreReglagesClavierPuisAttend() }
                    secondaire("Utiliser Ctrl droit") { controleur.basculeVersCtrlDroit() }
                } else {
                    principal("Libérer la touche") { controleur.libereLaTouche() }
                    secondaire("Utiliser Ctrl droit") { controleur.basculeVersCtrlDroit() }
                }

            case .modele:
                principal(controleur.incidentModele == nil ? "Télécharger" : "Réessayer") {
                    Task { await controleur.installeModele() }
                }

            case .redemarrage:
                principal("Redémarrer Lux Vox") { Self.redemarre() }

            case .geste:
                principal("Terminer") { controleur.fermeMiseEnRoute() }
            }

            Spacer(minLength: 0)

            if etape != .geste {
                Button("Passer") { controleur.fermeMiseEnRoute() }
                    .buttonStyle(.plain)
                    .foregroundStyle(LuxColor.textTertiary(.dark))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .font(.system(size: 12))
    }

    private func principal(_ titre: String, _ action: @escaping () -> Void) -> some View {
        Button(titre, action: action)
            .buttonStyle(.borderedProminent)
            .tint(LuxColor.accent(.dark))
            .keyboardShortcut(.defaultAction)
    }

    private func secondaire(_ titre: String, _ action: @escaping () -> Void) -> some View {
        Button(titre, action: action)
            .buttonStyle(.bordered)
    }

    /// Relance l'app : une nouvelle instance est ouverte, puis celle-ci se
    /// termine. Si le système refuse, l'utilisateur garde la main — le message
    /// lui dit quoi faire.
    private static func redemarre() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, _ in
            Task { @MainActor in NSApplication.shared.terminate(nil) }
        }
    }
}
