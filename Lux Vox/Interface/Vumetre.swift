//
//  Vumetre.swift
//  Lux Vox
//

import SwiftUI

/// Les barres qui suivent la voix, dans leur capsule.
///
/// Huit barres, pas cinquante. Une bande dense montre un signal ; huit barres
/// montrent un niveau, et c'est la seule chose que l'app a à dire. Elles ne
/// défilent pas — chacune reste à sa place et respire — donc rien ici ne
/// ressemble à un enregistrement qui se déroule.
///
/// **Au silence, les barres deviennent des points.** C'est la même primitive
/// arrivée à sa hauteur minimale, où elle est ronde. L'état de repos n'est
/// donc pas une autre image : c'est la même, au repos.
struct Vumetre: View {
    let signal: DictationState.Signal
    let niveau: NiveauLisse

    static let nombre = 8
    static let largeurBarre: CGFloat = 4
    static let espace: CGFloat = 2.5
    static let hauteur: CGFloat = 40
    /// Ce qui reste de chaque côté des barres. Large : les barres ne doivent
    /// pas venir toucher le liseré, sinon la capsule lit comme une jauge
    /// pleine à ras bord au lieu d'un objet qui respire.
    static let margeInterieure: CGFloat = 14

    private static let hauteurMax: CGFloat = 24
    /// Égale à la largeur : la barre est alors un cercle parfait.
    private static var hauteurMin: CGFloat { largeurBarre }

    static var largeurBarres: CGFloat {
        CGFloat(nombre) * largeurBarre + CGFloat(nombre - 1) * espace
    }

    static var largeur: CGFloat { largeurBarres + margeInterieure * 2 }

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(LuxColor.hudFond)

            // Le liseré remplace le halo, le flou et l'ombre de la version
            // précédente. Un trait clair sur du noir se détache de tout, sans
            // rien ajouter autour de la capsule.
            Capsule(style: .continuous)
                .strokeBorder(LuxColor.hudTrait, lineWidth: 2)

            TimelineView(.animation(minimumInterval: nil, paused: signal == .eteint)) { contexte in
                Canvas(opaque: false) { dessin, taille in
                    trace(dessin, taille, contexte.date)
                }
            }
        }
        .frame(width: Self.largeur, height: Self.hauteur)
        .allowsHitTesting(false)
        .accessibilityLabel(libelle)
    }

    private func trace(_ dessin: GraphicsContext, _ taille: CGSize, _ date: Date) {
        let temps = date.timeIntervalSinceReferenceDate
        let depart = (taille.width - Self.largeurBarres) / 2

        for rang in 0..<Self.nombre {
            let hauteur = Self.hauteurMin
                + (Self.hauteurMax - Self.hauteurMin) * part(rang, date: date, temps: temps)
            let barre = CGRect(
                x: depart + CGFloat(rang) * (Self.largeurBarre + Self.espace),
                y: (taille.height - hauteur) / 2,
                width: Self.largeurBarre,
                height: hauteur
            )
            dessin.fill(
                Path(roundedRect: barre, cornerRadius: Self.largeurBarre / 2),
                with: .color(LuxColor.hudTrait)
            )
        }
    }

    private func part(_ rang: Int, date: Date, temps: Double) -> CGFloat {
        switch signal {
        case .eteint:
            0
        case .capte:
            CGFloat(niveau.valeur(a: date)) * agitation(rang, temps: temps)
        case .travaille:
            0.14 + 0.52 * balayage(rang, temps: temps)
        }
    }

    /// Ce qui empêche les dix barres de monter comme un seul bloc.
    ///
    /// Deux sinusoïdes lentes déphasées barre par barre : le niveau commande
    /// l'ensemble, l'agitation lui donne son grain. Les périodes ne sont pas
    /// dans un rapport entier, donc le motif ne se répète pas.
    private func agitation(_ rang: Int, temps: Double) -> CGFloat {
        let dephasage = Double(rang) * 0.9
        let a = sin(temps * 6.1 + dephasage)
        let b = sin(temps * 3.7 - dephasage * 1.7)
        return CGFloat(0.52 + 0.48 * (a * 0.6 + b * 0.4))
    }

    /// Pendant la transcription il n'y a plus de voix : une bosse traverse les
    /// barres. Le seul état qui bouge tout seul, donc le seul qu'on reconnaît
    /// sans le chercher.
    private func balayage(_ rang: Int, temps: Double) -> CGFloat {
        let position = Double(rang) / Double(Self.nombre - 1)
        let passage = (temps / 1.5).truncatingRemainder(dividingBy: 1)
        let ecart = abs(position - passage)
        return CGFloat(exp(-pow(min(ecart, 1 - ecart) / 0.18, 2)))
    }

    private var libelle: String {
        switch signal {
        case .eteint: "Lux Vox au repos"
        case .capte: "Lux Vox écoute"
        case .travaille: "Lux Vox transcrit"
        }
    }
}

#Preview("Vumètre") {
    VStack(spacing: 22) {
        Vumetre(signal: .capte, niveau: NiveauLisse())
        Vumetre(signal: .travaille, niveau: NiveauLisse())
    }
    .padding(30)
    .background(Color(white: 0.85))
}
