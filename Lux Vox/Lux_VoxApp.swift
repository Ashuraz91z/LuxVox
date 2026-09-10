//
//  Lux_VoxApp.swift
//  Lux Vox
//

import AppKit
import SwiftUI

/// Lux Vox est un agent (`LSUIElement`) : pas d'icône dans le Dock, pas de
/// fenêtre principale.
///
/// Ce qui se voit pendant une dictée est un petit panneau flottant en bas de
/// l'écran (voir `OverlayController`). La barre des menus ne sert qu'aux
/// réglages et, plus tard, à l'historique.
@main
struct Lux_VoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegue

    var body: some Scene {
        MenuBarExtra("Lux Vox", systemImage: "waveform") {
            MenuBarView(controleur: delegue.controleur, amont: delegue.amont)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Le déclencheur doit être armé dès le lancement.
///
/// Le poser sur la vue du panneau déroulant ne marcherait pas : `MenuBarExtra`
/// ne construit son contenu qu'à la première ouverture du menu, et la dictée
/// resterait muette jusque-là.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controleur = DictationController()
    /// La veille des versions. Elle vit ici et non dans le contrôleur : elle
    /// n'a rien à voir avec la dictée, et un objet qui parle au réseau n'a
    /// rien à faire dans celui qui écoute le micro.
    let amont = MiseAJour()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controleur.demarre()
        amont.demarre()
    }
}



