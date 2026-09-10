//
//  MiseEnRouteTests.swift
//  Lux VoxTests
//

import Testing
@testable import Lux_Vox

/// L'enchaînement des bulles, vérifié sans barre des menus, sans permission et
/// sans écran : ce qu'il reste à régler est fourni par le test.
///
/// C'est le seul endroit où cet enchaînement se voit en entier. À l'usage il
/// ne se montre qu'une fois par machine, et une erreur — une bulle qui
/// réapparaît, une étape sautée à tort — ne se remarquerait qu'au premier
/// lancement de quelqu'un d'autre.
@Suite("Mise en route — enchaînement des bulles")
struct MiseEnRouteTests {

    /// Une machine où tout est déjà en règle. Des fonctions plutôt que des
    /// constantes : une fermeture rangée dans une propriété statique n'est pas
    /// `Sendable`, et le mode Swift 6 la refuse.
    static func toutEstFait(_ etape: EtapeMiseEnRoute) -> Bool { false }

    /// Une machine neuve : rien n'est accordé, rien n'est téléchargé. Le
    /// redémarrage, lui, n'est jamais dû tant que rien n'a été installé.
    static func rienNEstFait(_ etape: EtapeMiseEnRoute) -> Bool { etape != .redemarrage }

    // MARK: - La visite

    @Test("Une machine en règle ne voit que la présentation et le geste")
    func visiteMinimale() {
        #expect(EtapeMiseEnRoute.visite(aRegler: Self.toutEstFait(_:)) == [.presentation, .geste])
    }

    @Test("Une machine neuve voit tout ce qui reste à régler, dans l'ordre")
    func visiteComplete() {
        #expect(EtapeMiseEnRoute.visite(aRegler: Self.rienNEstFait(_:)) == [
            .presentation, .micro, .accessibilite, .touche, .modele, .geste,
        ])
    }

    @Test("Le redémarrage n'est proposé que lorsqu'il est dû")
    func redemarrageSeulementSiDu() {
        let visite = EtapeMiseEnRoute.visite { $0 == .redemarrage }
        #expect(visite == [.presentation, .redemarrage, .geste])
    }

    // MARK: - L'avancement

    @Test("Chaque bulle mène à la suivante")
    func enchainement() {
        let visite = EtapeMiseEnRoute.visite(aRegler: Self.rienNEstFait(_:))
        var etape = EtapeMiseEnRoute.presentation
        var vues: [EtapeMiseEnRoute] = [etape]

        while etape != .geste {
            etape = EtapeMiseEnRoute.apres(etape, dans: visite, aRegler: Self.rienNEstFait(_:))
            vues.append(etape)
        }

        #expect(vues == visite)
    }

    /// Le cas qui a motivé le passage par une fonction plutôt qu'un index :
    /// on accorde le micro *et* l'Accessibilité d'un coup dans les Réglages
    /// Système, alors qu'on n'en était qu'au micro.
    @Test("Une étape réglée entre-temps est sautée")
    func etapeReglagePendantLaVisite() {
        let visite = EtapeMiseEnRoute.visite(aRegler: Self.rienNEstFait(_:))

        let suivante = EtapeMiseEnRoute.apres(.micro, dans: visite) { etape in
            switch etape {
            case .accessibilite: false  // accordée pendant qu'on était sur le micro
            case .redemarrage: false
            default: true
            }
        }

        #expect(suivante == .touche)
    }

    @Test("Une étape sautée garde son point dans les jalons")
    func lesJalonsNeBougentPas() {
        // La visite est arrêtée à l'ouverture : rien de ce qui se règle
        // ensuite ne doit faire rétrécir la rangée de points sous l'œil.
        let visite = EtapeMiseEnRoute.visite(aRegler: Self.rienNEstFait(_:))
        #expect(visite.count == 6)
        #expect(visite.contains(.accessibilite))
    }

    @Test("La dernière bulle est toujours le geste")
    func finDeVisite() {
        let visite = EtapeMiseEnRoute.visite(aRegler: Self.toutEstFait(_:))
        #expect(EtapeMiseEnRoute.apres(.geste, dans: visite, aRegler: Self.toutEstFait(_:)) == .geste)
    }

    /// Une étape hors visite ne doit pas faire tourner l'enchaînement à vide.
    @Test("Une étape absente de la visite mène droit au geste")
    func etapeHorsVisite() {
        let visite = EtapeMiseEnRoute.visite(aRegler: Self.toutEstFait(_:))
        #expect(EtapeMiseEnRoute.apres(.modele, dans: visite, aRegler: Self.toutEstFait(_:)) == .geste)
    }

    // MARK: - Ce que chaque bulle a à dire

    @Test("Seule la présentation n'a pas de rubrique — elle porte la marque")
    func rubriques() {
        for etape in EtapeMiseEnRoute.allCases where etape != .presentation {
            #expect(etape.rubrique != nil, "\(etape.rawValue) doit avoir une rubrique")
        }
        #expect(EtapeMiseEnRoute.presentation.rubrique == nil)
    }
}

/// La correspondance des valeurs de `AppleFnUsageType`, relevée à l'écran dans
/// le panneau Clavier — `0` y affiche « Ne rien faire », `3` « Lancer la dictée
/// (appuyer deux fois sur 🌐) ».
///
/// Rien ici n'écrit dans le système : un test qui change un réglage de la
/// machine qui le fait tourner est un test qu'on n'ose plus lancer. Ce qui se
/// vérifie ici, c'est la table — se tromper de valeur reviendrait à demander à
/// macOS d'attacher la dictée d'Apple à la touche en croyant l'en détacher.
@Suite("Touche 🌐 — correspondance des valeurs")
struct ReglageDuGlobeTests {

    @Test("Zéro est la valeur qui libère la touche")
    func zeroLibere() {
        #expect(ReglageDuGlobe.rienFaire.rawValue == 0)
    }

    @Test("La dictée d'Apple est une valeur de ce réglage, pas un réglage à part")
    func dicteeDansLaMemeTable() {
        // C'est ce qui rend l'étape automatisable : une seule clé commande le
        // simple appui *et* le double-appui.
        #expect(ReglageDuGlobe.dicteeDApple.rawValue == 3)
        #expect(ReglageDuGlobe(rawValue: 3) == .dicteeDApple)
    }

    @Test("Les quatre valeurs sont distinctes et contiguës")
    func tableComplete() {
        #expect(ReglageDuGlobe.allCases.map(\.rawValue) == [0, 1, 2, 3])
    }

    @Test("Chaque valeur se nomme, pour que la bulle dise ce qu'on abandonne")
    func libelles() {
        for usage in ReglageDuGlobe.allCases {
            #expect(!usage.libelle.isEmpty)
        }
        #expect(ReglageDuGlobe.sourceDeSaisie.libelle == "Changer de source de saisie")
    }
}
