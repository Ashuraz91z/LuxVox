//
//  MenuBarLaunchUITests.swift
//  Lux VoxUITests
//

import XCTest

/// Lux Vox est un agent : le seul comportement de lancement qui se vérifie de
/// l'extérieur est qu'il démarre et n'ouvre **aucune** fenêtre.
///
/// Le test de performance de lancement du modèle Xcode a été retiré : il mesure
/// l'ouverture d'une fenêtre principale, que cette app n'a pas.
final class MenuBarLaunchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLancementSansFenetre() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertNotEqual(app.state, .notRunning, "L'app doit démarrer.")
        XCTAssertEqual(
            app.windows.count, 0,
            "Une app LSUIElement ne doit ouvrir aucune fenêtre au lancement."
        )
    }
}
