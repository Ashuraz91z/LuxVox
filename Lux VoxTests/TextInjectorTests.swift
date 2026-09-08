//
//  TextInjectorTests.swift
//  Lux VoxTests
//

import Testing
@testable import Lux_Vox

/// Le découpage en paquets de la décision *c*.
///
/// Les applications Electron et les terminaux perdent des événements
/// synthétiques envoyés trop vite : le texte part par petits paquets. Ce qu'on
/// vérifie ici, c'est qu'aucun caractère ne se perd ni ne se coupe en route —
/// le reste de l'injection demande un vrai clavier et une vraie fenêtre.
@Suite("Injection — découpage")
struct TextInjectorTests {

    private func recompose(_ paquets: [[UInt16]]) -> String {
        String(decoding: paquets.flatMap { $0 }, as: UTF16.self)
    }

    @Test("Un texte court tient en un seul paquet")
    func texteCourt() {
        let paquets = TextInjector.paquets(de: "Bonjour")
        #expect(paquets.count == 1)
        #expect(recompose(paquets) == "Bonjour")
    }

    @Test("Un texte long est découpé sans rien perdre")
    func texteLong() {
        let texte = String(repeating: "abcde ", count: 40)
        let paquets = TextInjector.paquets(de: texte)

        #expect(paquets.count > 1)
        #expect(recompose(paquets) == texte)
        for paquet in paquets {
            #expect(paquet.count <= TextInjector.taillePaquet)
        }
    }

    @Test("Les accents survivent au découpage")
    func accents() {
        let texte = "Le rendez-vous est décalé à après-midi, c'est ça ?"
        #expect(recompose(TextInjector.paquets(de: texte)) == texte)
    }

    /// Une paire de substitution coupée en deux n'est plus un caractère : la
    /// moitié envoyée seule produirait un losange noir.
    @Test("Une paire de substitution n'est jamais coupée")
    func pairesDeSubstitution() {
        let texte = String(repeating: "🙂", count: 15)
        let paquets = TextInjector.paquets(de: texte)

        #expect(recompose(paquets) == texte)
        for paquet in paquets {
            #expect(paquet.count.isMultiple(of: 2), "un émoji a été coupé en deux")
            #expect(paquet.count <= TextInjector.taillePaquet)
        }
    }

    @Test("Un texte vide ne produit aucun paquet")
    func texteVide() {
        #expect(TextInjector.paquets(de: "").isEmpty)
    }

    @Test("Le seuil du presse-papier reste au-dessus de la taille de paquet")
    func seuilsCoherents() {
        #expect(TextInjector.seuilPressePapier > TextInjector.taillePaquet)
    }
}
