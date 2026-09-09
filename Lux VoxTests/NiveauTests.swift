//
//  NiveauTests.swift
//  Lux VoxTests
//

import Testing
import AVFoundation
@testable import Lux_Vox

/// La mesure du niveau sonore qui alimente la courbe.
///
/// Elle tourne sur le thread temps réel du micro, où une erreur ne se voit pas :
/// elle se traduit seulement par une animation qui ne bouge pas, ou qui sature.
@Suite("Mesure du niveau")
struct MesureDuNiveauTests {

    /// Fabrique un tampon rempli d'une sinusoïde d'amplitude donnée.
    private func tampon(amplitude: Float, trames: Int = 8192) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
            channels: 1, interleaved: false
        )!
        let tampon = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(trames))!
        tampon.frameLength = AVAudioFrameCount(trames)
        let canal = tampon.floatChannelData![0]
        for index in 0..<trames {
            canal[index] = amplitude * sin(Float(index) * 0.1)
        }
        return tampon
    }

    @Test("Un tampon est découpé en plusieurs mesures")
    func plusieursMesuresParTampon() {
        // Une seule valeur par tampon donnerait six points par seconde :
        // beaucoup trop peu pour suivre la voix.
        #expect(AudioCapture.mesure(tampon(amplitude: 0.2)).count >= 8)
    }

    @Test("Le silence ne fait rien bouger")
    func silence() {
        let mesures = AudioCapture.mesure(tampon(amplitude: 0))
        #expect(!mesures.isEmpty)
        #expect(mesures.allSatisfy { $0 == 0 })
    }

    @Test("Un signal fort sature l'affichage")
    func signalFort() {
        let mesures = AudioCapture.mesure(tampon(amplitude: 1))
        #expect(mesures.allSatisfy { $0 == 1 })
    }

    @Test("Toute mesure reste dans les bornes de l'affichage")
    func bornes() {
        for amplitude: Float in [0, 0.0001, 0.01, 0.1, 0.5, 1, 4] {
            for mesure in AudioCapture.mesure(tampon(amplitude: amplitude)) {
                #expect(mesure >= 0 && mesure <= 1, "hors bornes pour \(amplitude)")
            }
        }
    }

    /// C'est la propriété qui compte pour l'œil : parler plus fort doit lever
    /// les traits, jamais l'inverse.
    @Test("Plus le son est fort, plus la mesure est haute")
    func croissance() {
        func moyenne(_ amplitude: Float) -> Float {
            let m = AudioCapture.mesure(tampon(amplitude: amplitude))
            return m.reduce(0, +) / Float(m.count)
        }
        let paliers: [Float] = [0.001, 0.01, 0.05, 0.2]
        let mesures = paliers.map(moyenne)
        for (precedent, suivant) in zip(mesures, mesures.dropFirst()) {
            #expect(suivant >= precedent)
        }
        #expect(mesures.last! > mesures.first!)
    }

    @Test("Un tampon vide ne produit aucune mesure")
    func tamponVide() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
            channels: 1, interleaved: false
        )!
        let vide = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        vide.frameLength = 0
        #expect(AudioCapture.mesure(vide).isEmpty)
    }
}


/// Le lissage qui transforme six salves par seconde en une courbe continue.
///
/// C'est le seul endroit où une erreur d'affichage se voit sans se debugger :
/// une constante inversée donne une courbe qui traîne à la montée et claque à
/// la descente, ce qui ne ressemble plus du tout à une voix.
@Suite("Niveau lissé")
struct NiveauLisseTests {

    private let origine = Date(timeIntervalSinceReferenceDate: 0)

    private func apres(_ secondes: Double) -> Date {
        origine.addingTimeInterval(secondes)
    }

    @Test("Au démarrage, rien ne bouge")
    func depart() {
        #expect(NiveauLisse().valeur(a: .now) == 0)
    }

    @Test("La valeur converge vers la cible")
    func convergence() {
        var niveau = NiveauLisse()
        niveau.vise(1, a: origine)

        #expect(niveau.valeur(a: origine) < 0.05)
        #expect(niveau.valeur(a: apres(1)) > 0.95)
    }

    @Test("La montée est plus rapide que la descente")
    func montePlusViteQueCaDescend() {
        // Une syllabe attaque net et traîne : c'est cette asymétrie qui fait
        // qu'on reconnaît sa voix dans la courbe plutôt qu'un signal.
        var monte = NiveauLisse()
        monte.vise(1, a: origine)
        let gagne = monte.valeur(a: apres(0.08))

        var descend = NiveauLisse()
        descend.vise(1, a: origine.addingTimeInterval(-10))
        descend.vise(0, a: origine)
        let perdu = 1 - descend.valeur(a: apres(0.08))

        #expect(gagne > perdu)
    }

    @Test("La valeur reste dans les bornes de l'affichage")
    func bornes() {
        var niveau = NiveauLisse()
        for (rang, cible) in [0.0, 1, 0.3, 1, 0, 0.8].enumerated() {
            niveau.vise(cible, a: apres(Double(rang) * 0.17))
            for instant in stride(from: 0.0, through: 0.17, by: 0.01) {
                let valeur = niveau.valeur(a: apres(Double(rang) * 0.17 + instant))
                #expect(valeur >= 0 && valeur <= 1, "hors bornes après \(cible)")
            }
        }
    }

    @Test("Une cible hors bornes est ramenée dans la plage")
    func cibleAberrante() {
        var niveau = NiveauLisse()
        niveau.vise(4.2, a: origine)
        #expect(niveau.valeur(a: apres(2)) <= 1)

        niveau.vise(-3, a: apres(2))
        #expect(niveau.valeur(a: apres(4)) >= 0)
    }

    /// Le cas qui casse un lissage naïf : une salve arrive avant la fin de la
    /// décroissance précédente. Repartir de l'ancienne cible ferait sauter la
    /// courbe en arrière.
    @Test("Une salve en cours de course repart de la valeur courante")
    func salveEnPleineCourse() {
        var niveau = NiveauLisse()
        niveau.vise(1, a: origine)
        let aMiChemin = niveau.valeur(a: apres(0.03))

        niveau.vise(0.2, a: apres(0.03))
        #expect(abs(niveau.valeur(a: apres(0.03)) - aMiChemin) < 0.001)
    }
}
