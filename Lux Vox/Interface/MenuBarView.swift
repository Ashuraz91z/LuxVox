//
//  MenuBarView.swift
//  Lux Vox
//

import SwiftUI

/// Le panneau déroulant : 280 pt de large (DA §7), pas de titre, pas d'ombre.
///
/// Il ne porte pour l'instant que ce dont le déclencheur a besoin — la
/// permission et le choix de la touche. L'historique des dix dernières
/// transcriptions viendra ici.
struct MenuBarView: View {
    @Bindable var controleur: DictationController
    let amont: MiseAJour
    @Environment(\.colorScheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            entete

            if !controleur.accessibiliteAccordee {
                permission(
                    titre: "ACCESSIBILITÉ",
                    explication: "Sans cette permission, Lux Vox ne peut pas lire la touche de déclenchement.",
                    accorder: { controleur.demandeAccessibilite() },
                    reglages: { controleur.ouvreReglagesAccessibilite() }
                )
            }

            if !controleur.microAccorde {
                permission(
                    titre: "MICROPHONE",
                    explication: "Sans micro, rien à transcrire.",
                    accorder: { Task { await controleur.demandeMicro() } },
                    reglages: { controleur.ouvreReglagesMicro() }
                )
            }

            modele

            if let incident = controleur.dernierIncident {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    rubrique("DERNIÈRE DICTÉE")
                    Text(incident)
                        .font(.system(size: 12))
                        .foregroundStyle(LuxColor.important(theme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !controleur.dernierTexte.isEmpty {
                Divider()
                derniereTranscription
            }

            Divider()
            choixDuDeclencheur

            Divider()
            miseAJour

            Divider()
            piedDePage
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
    }

    private var entete: some View {
        HStack(spacing: 10) {
            MarqueVox(taille: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text("Lux Vox")
                    .font(.system(size: 13))
                    .foregroundStyle(LuxColor.text(theme))
                Text(resume)
                    .font(.system(size: 12))
                    .foregroundStyle(LuxColor.textSecondary(theme))
            }
        }
    }

    private var resume: String {
        guard controleur.accessibiliteAccordee else { return "En attente de permission" }
        guard controleur.etatModele.estPret else { return "Modèle à télécharger" }
        guard controleur.moteurPret else { return "Préparation du moteur…" }
        return switch controleur.etat {
        case .repos: "Prêt — maintenez \(controleur.declencheur.libelle)"
        case .ecoute: "Écoute"
        case .ecouteVerrouillee: "Écoute verrouillée"
        case .traitement: "Transcription"
        }
    }

    /// Le bouton ouvre l'alerte système native, pas un écran dessiné : c'est le
    /// seul langage que l'utilisateur croit quand il s'agit d'accorder un
    /// pouvoir sur son clavier ou son micro (DA §9).
    private func permission(
        titre: String,
        explication: String,
        accorder: @escaping () -> Void,
        reglages: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            rubrique(titre)

            Text(explication)
                .font(.system(size: 12))
                .foregroundStyle(LuxColor.textSecondary(theme))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Accorder", action: accorder)
                Button("Réglages Système", action: reglages)
            }
            .font(.system(size: 12))
        }
    }

    /// L'état du modèle. Il n'y a pas de mode dégradé : tant qu'il n'est pas
    /// installé, l'app ne transcrit rien, et le dit ici.
    @ViewBuilder
    private var modele: some View {
        switch controleur.etatModele {
        case .pret:
            EmptyView()

        case .aInstaller:
            VStack(alignment: .leading, spacing: 6) {
                rubrique("MODÈLE FRANÇAIS")
                Text("Environ 650 Mo, téléchargés une fois. Ensuite, tout fonctionne hors ligne.")
                    .font(.system(size: 12))
                    .foregroundStyle(LuxColor.textSecondary(theme))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Télécharger") { Task { await controleur.installeModele() } }
                    .font(.system(size: 12))
            }

        case .installation(let avancement):
            VStack(alignment: .leading, spacing: 6) {
                rubrique("MODÈLE FRANÇAIS")
                ProgressView(value: avancement)
                Text(avancement < 1 ? "Téléchargement…" : "Préparation du moteur…")
                    .font(.system(size: 12))
                    .foregroundStyle(LuxColor.textSecondary(theme))
            }

        case .indisponible(let raison):
            VStack(alignment: .leading, spacing: 6) {
                rubrique("MODÈLE FRANÇAIS")
                Text(raison)
                    .font(.system(size: 12))
                    .foregroundStyle(LuxColor.important(theme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Filet de sécurité tant que l'injection n'existe pas : le texte reste
    /// consultable et copiable à la main.
    private var derniereTranscription: some View {
        VStack(alignment: .leading, spacing: 4) {
            rubrique("DERNIÈRE TRANSCRIPTION")
            Text(controleur.dernierTexte)
                .font(.system(size: 13))
                .foregroundStyle(LuxColor.text(theme))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let latence = controleur.derniereLatence {
                Text(Self.enSecondes(latence))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(LuxColor.textTertiary(theme))
            }
        }
    }

    private func rubrique(_ titre: String) -> some View {
        Text(titre)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.55)
            .foregroundStyle(LuxColor.textTertiary(theme))
    }

    private static func enSecondes(_ duree: Duration) -> String {
        let secondes = Double(duree.components.seconds)
            + Double(duree.components.attoseconds) / 1e18
        return String(format: "%.2f s", secondes)
    }

    private var choixDuDeclencheur: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DÉCLENCHEUR")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.55)
                .foregroundStyle(LuxColor.textTertiary(theme))

            Picker("", selection: $controleur.declencheur) {
                ForEach(KeyboardTrigger.Declencheur.allCases) { touche in
                    Text(touche.libelle).tag(touche)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)

            if controleur.declencheur == .globe {
                Button("Régler la touche 🌐 dans les Réglages…") {
                    controleur.ouvreReglagesClavier()
                }
                .font(.system(size: 12))
                .buttonStyle(.link)
                .help("macOS s'attribue cette touche par défaut. Réglez « Appuyer sur 🌐 pour » sur « Ne rien faire ».")
            }
        }
    }

    /// La veille des versions.
    ///
    /// Elle n'est bruyante que quand elle a quelque chose à dire. Le reste du
    /// temps elle tient sur une ligne, et cette ligne est le seul endroit où
    /// l'utilisateur apprend que l'app va voir chez GitHub de temps en temps.
    /// La cacher entièrement aurait été plus propre à l'œil et moins honnête.
    @ViewBuilder
    private var miseAJour: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch amont.etat {
            case .inconnu, .verification:
                murmure("Recherche d'une mise à jour…")

            case .aJour:
                HStack {
                    murmure("Version \(amont.courante.description) — à jour")
                    Spacer()
                    lienDiscret("Vérifier") { amont.verifie() }
                }

            case .echec(let raison):
                HStack {
                    murmure(raison)
                    Spacer()
                    lienDiscret("Réessayer") { amont.verifie() }
                }

            case .disponible(let version):
                rubrique("MISE À JOUR")
                Text("Lux Vox \(version.description) est disponible.")
                    .font(.system(size: 12))
                    .foregroundStyle(LuxColor.text(theme))
                Button("Télécharger") { amont.telecharge() }
                    .font(.system(size: 12))

            case .telechargement(let version):
                rubrique("MISE À JOUR")
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    murmure("Téléchargement de \(version.description)…")
                }

            case .pret(let version, _):
                rubrique("MISE À JOUR")
                Text("Lux Vox \(version.description) est dans vos téléchargements.")
                    .font(.system(size: 12))
                    .foregroundStyle(LuxColor.text(theme))
                    .fixedSize(horizontal: false, vertical: true)
                // L'app ne peut pas se remplacer elle-même : il y faudrait une
                // signature Developer ID et une notarisation. Tant qu'elle ne
                // les a pas, le dernier geste appartient à l'utilisateur, et
                // se taire là-dessus laisserait quelqu'un croire que c'est
                // fait.
                murmure("Quittez Lux Vox, puis glissez la nouvelle version dans Applications.")
                Button("Afficher dans le Finder") { amont.montreDansLeFinder() }
                    .font(.system(size: 12))
            }
        }
    }

    private func murmure(_ texte: String) -> some View {
        Text(texte)
            .font(.system(size: 11.5))
            .foregroundStyle(LuxColor.textTertiary(theme))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func lienDiscret(_ titre: String, action: @escaping () -> Void) -> some View {
        Button(titre, action: action)
            .buttonStyle(.link)
            .font(.system(size: 11.5))
    }

    /// La mise en route ne se rouvre jamais d'elle-même une fois tout accordé
    /// (DA §9) : c'est par ici qu'on la retrouve — pour revoir le geste, ou
    /// reprendre un téléchargement abandonné.
    private var piedDePage: some View {
        HStack {
            Button("Mise en route…") { controleur.ouvreMiseEnRoute() }
            Spacer()
            Button("Quitter") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .font(.system(size: 12))
    }
}
