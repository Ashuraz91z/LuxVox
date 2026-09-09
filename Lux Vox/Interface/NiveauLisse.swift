//
//  NiveauLisse.swift
//  Lux Vox
//

import Foundation

/// Le niveau du micro, lissé pour l'affichage.
///
/// Le micro ne livre pas un flux continu : il livre une salve toutes les
/// 170 ms. Branchée telle quelle sur une courbe, l'amplitude sauterait six
/// fois par seconde — l'œil verrait des à-coups, pas une voix.
///
/// La valeur n'est donc pas stockée : elle se **calcule** à l'instant où on la
/// demande, par décroissance exponentielle vers la dernière cible reçue. C'est
/// ce qui permet à la courbe de continuer à vivre entre deux salves, et de se
/// dessiner à 60 images par seconde à partir de six mesures.
nonisolated struct NiveauLisse: Equatable, Sendable {

    private(set) var depart: Double = 0
    private(set) var cible: Double = 0
    private(set) var instant = Date.distantPast
    private(set) var constante = Self.descente

    /// Monter vite, redescendre lentement. C'est ainsi qu'une voix s'entend —
    /// l'attaque d'une syllabe est nette, sa queue traîne — et une descente
    /// brusque ferait clignoter la courbe entre deux mots.
    static let montee = 0.05
    static let descente = 0.20

    /// La valeur à cet instant. Analytique, donc juste quel que soit le
    /// moment où on la demande, et sans état à faire avancer.
    func valeur(a date: Date) -> Double {
        let ecoule = date.timeIntervalSince(instant)
        guard ecoule > 0 else { return depart }
        return cible + (depart - cible) * exp(-ecoule / constante)
    }

    /// Enregistre une nouvelle cible. Le départ est la valeur courante, pas la
    /// cible précédente : sans ça, une salve qui arrive avant la fin de la
    /// décroissance ferait repartir la courbe d'un point qu'elle a déjà quitté.
    mutating func vise(_ nouvelle: Double, a date: Date = .now) {
        let courante = valeur(a: date)
        depart = courante
        cible = min(max(nouvelle, 0), 1)
        instant = date
        constante = cible > courante ? Self.montee : Self.descente
    }
}
