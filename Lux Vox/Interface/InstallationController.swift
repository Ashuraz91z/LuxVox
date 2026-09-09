//
//  InstallationController.swift
//  Lux Vox
//

import AppKit
import SwiftUI

/// Les étapes de la première mise en route, telles qu'elles se voient.
nonisolated enum EtapeInstallation: Equatable, Sendable {
    /// Téléchargement du modèle, avec sa progression.
    case telechargement(Double)
    /// Le modèle est là. Charger dans la foulée s'est révélé peu fiable :
    /// l'app restait figée sur la préparation, alors qu'un simple redémarrage
    /// règle tout. On demande donc la relance plutôt que de faire attendre
    /// devant un écran dont on ne sait pas s'il avance.
    case terminee
    case echec(String)

    var titre: String {
        switch self {
        case .telechargement: "Téléchargement du modèle"
        case .terminee: "Modèle installé"
        case .echec: "Installation interrompue"
        }
    }

    var detail: String {
        switch self {
        case .telechargement(let part):
            "\(Int(part * 100)) % de 626 Mo — une seule fois, puis tout fonctionne hors ligne."
        case .terminee:
            "Redémarrez Lux Vox pour terminer la mise en route. Le moteur se prépare au prochain lancement — comptez une minute, une seule fois."
        case .echec(let raison):
            raison
        }
    }
}

@MainActor
@Observable
final class InstallationModel {
    var etape: EtapeInstallation = .telechargement(0)
}

/// La fenêtre de mise en route.
///
/// Elle existe pour une raison précise : entre le clic sur « Télécharger » et
/// la première dictée, il se passe près de deux minutes. Sans surface visible,
/// l'app paraît ne rien faire — et la progression cachée dans le menu déroulant
/// oblige à aller la chercher, ce qui revient au même.
@MainActor
final class InstallationController {

    private let modele = InstallationModel()
    private var fenetre: NSWindow?

    func montre(_ etape: EtapeInstallation) {
        modele.etape = etape

        let fenetre = fenetreExistanteOuNouvelle()
        if !fenetre.isVisible {
            fenetre.center()
            NSApp.activate(ignoringOtherApps: true)
            fenetre.makeKeyAndOrderFront(nil)
        }
    }

    func ferme() {
        fenetre?.orderOut(nil)
    }

    private func fenetreExistanteOuNouvelle() -> NSWindow {
        if let fenetre { return fenetre }

        let nouvelle = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 190),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        nouvelle.title = "Lux Vox"
        nouvelle.titlebarAppearsTransparent = true
        nouvelle.isMovableByWindowBackground = true
        nouvelle.hasShadow = true
        nouvelle.isReleasedWhenClosed = false
        nouvelle.level = .floating
        nouvelle.contentView = NSHostingView(rootView: InstallationView(modele: modele))

        fenetre = nouvelle
        return nouvelle
    }
}

struct InstallationView: View {
    @Bindable var modele: InstallationModel
    @Environment(\.colorScheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                MarqueVox(taille: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(modele.etape.titre)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LuxColor.text(theme))
                    Text("Lux Vox")
                        .font(.system(size: 12))
                        .foregroundStyle(LuxColor.textTertiary(theme))
                }
            }

            indicateur

            Text(modele.etape.detail)
                .font(.system(size: 12))
                .foregroundStyle(estEnEchec ? LuxColor.important(theme) : LuxColor.textSecondary(theme))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                switch modele.etape {
                case .terminee:
                    Button("Redémarrer Lux Vox") { Self.redemarre() }
                        .keyboardShortcut(.defaultAction)
                case .echec:
                    Button("Quitter") { NSApplication.shared.terminate(nil) }
                case .telechargement:
                    EmptyView()
                }
            }
        }
        .padding(20)
        .frame(width: 380, height: 190, alignment: .topLeading)
        .background(LuxColor.surfaceElevated(theme))
    }

    private var estEnEchec: Bool {
        if case .echec = modele.etape { return true }
        return false
    }

    @ViewBuilder
    private var indicateur: some View {
        switch modele.etape {
        case .telechargement(let part):
            ProgressView(value: part)
                .progressViewStyle(.linear)
        case .terminee, .echec:
            EmptyView()
        }
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
