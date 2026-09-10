//
//  MenuBarLaunchUITests.swift
//  Lux VoxUITests
//

import XCTest

/// Lux Vox est un agent : le seul comportement de lancement qui se vérifie de
/// l'extérieur est qu'il démarre sans ouvrir de fenêtre.
///
/// Le test de performance de lancement du modèle Xcode a été retiré : il mesure
/// l'ouverture d'une fenêtre principale, que cette app n'a pas.
final class MenuBarLaunchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// La mise en route est désarmée pour ce test, et ce n'est pas une
    /// commodité : son voile prend l'écran entier au niveau du volet système.
    /// Le laisser s'ouvrir ici confisquait l'écran de qui lance les tests,
    /// puis laissait derrière lui un panneau que le harnais n'arrivait pas à
    /// fermer — une minute de délai d'attente avant l'échec.
    ///
    /// Ce que le test garde est ce qu'il a toujours vérifié, et que rien
    /// d'autre ne couvre : une app agent n'a **pas** de fenêtre. Un
    /// `WindowGroup` ajouté par mégarde à la scène se verrait ici, et nulle
    /// part ailleurs avant la première exécution sur une autre machine.
    /// L'enchaînement du voile, lui, se vérifie en logique pure dans
    /// `MiseEnRouteTests`.
    @MainActor
    func testLancementSansFenetre() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-sansMiseEnRoute", "YES"]
        app.launch()

        XCTAssertNotEqual(app.state, .notRunning, "L'app doit démarrer.")
        XCTAssertEqual(
            app.windows.count, 0,
            "Une app LSUIElement n'ouvre aucune fenêtre d'elle-même."
        )
    }
}
