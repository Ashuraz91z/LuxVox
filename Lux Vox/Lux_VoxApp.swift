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
        MenuBarExtra("Lux Vox", systemImage: "mic") {
            MenuBarView(controleur: delegue.controleur)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        controleur.demarre()
    }
}
