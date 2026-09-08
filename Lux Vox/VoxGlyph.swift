//
//  VoxGlyph.swift
//  Lux Vox
//

import SwiftUI

/// La marque de Lux Vox : capsule, arceau, pied. Trois pièces, trois poids.
///
/// Les cotes viennent de la DA (§3), exprimées dans une boîte de 16 unités et
/// mises à l'échelle ici. Du plein, jamais du trait — sauf la capsule creuse et
/// l'arceau, et à trait épais.
///
/// L'état se lit à la **forme** : le remplissage de la capsule dit si l'app
/// travaille, la forme de l'arceau dit ce qu'elle fait. Les deux écoutes —
/// maintien et verrouillée — partagent volontairement le même glyphe (voir
/// `DictationState.arceau`).
struct VoxGlyph: View {
    let etat: DictationState
    var taille: CGFloat = 24

    @Environment(\.colorScheme) private var theme
    @State private var balayage: Double = 0

    private var echelle: CGFloat { taille / 16 }
    private var couleur: Color { LuxColor.accent(theme) }

    private var angles: ArceauAngles { etat.arceau }

    var body: some View {
        ZStack {
            CapsuleContour()
                .stroke(couleur, lineWidth: 1.25 * echelle)

            CapsuleRemplie(remplissage: etat.capsulePleine ? 1 : 0)
                .fill(couleur)

            Arceau(angleDebut: angles.debut, angleFin: angles.fin)
                .stroke(couleur, style: StrokeStyle(lineWidth: 1.35 * echelle, lineCap: .round))
                .rotationEffect(.degrees(etat == .traitement ? balayage : 0))

            Pied()
                .fill(couleur)
        }
        .frame(width: taille, height: taille)
        // DA §8 : la capsule se remplit du bas vers le haut en 0,12 s ;
        // les extrémités de l'arceau se rejoignent en 0,18 s.
        .animation(.easeOut(duration: 0.12), value: etat.capsulePleine)
        .animation(.easeInOut(duration: 0.18), value: angles.fin)
        .onChange(of: etat, initial: true) { _, nouveau in
            guard nouveau == .traitement else {
                balayage = 0
                return
            }
            balayage = 0
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                balayage = 360
            }
        }
        .accessibilityLabel(libelle)
    }

    private var libelle: String {
        switch etat {
        case .repos: "Lux Vox au repos"
        case .ecoute: "Lux Vox écoute"
        case .ecouteVerrouillee: "Lux Vox écoute, micro verrouillé"
        case .traitement: "Lux Vox transcrit"
        }
    }
}

// MARK: - Les trois pièces

/// `rect x=6.2 y=1.6 w=3.6 h=7.6 rx=1.8` — bouts entièrement arrondis, la même
/// primitive que les barres de Lux Md, dressée.
private nonisolated struct CapsuleContour: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: Corps.rect(dans: rect), cornerRadius: 1.8 * Corps.echelle(rect))
    }
}

/// Le remplissage monte du bas vers le haut, ce qui donne à la transition
/// « repos → écoute » son sens : la masse arrive, ça capte.
private nonisolated struct CapsuleRemplie: Shape {
    var remplissage: Double

    var animatableData: Double {
        get { remplissage }
        set { remplissage = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let corps = Corps.rect(dans: rect)
        let capsule = Path(roundedRect: corps, cornerRadius: 1.8 * Corps.echelle(rect))

        guard remplissage < 1 else { return capsule }
        guard remplissage > 0 else { return Path() }

        let hauteur = corps.height * remplissage
        let fenetre = CGRect(
            x: corps.minX, y: corps.maxY - hauteur,
            width: corps.width, height: hauteur
        )
        return Path(capsule.cgPath.intersection(Path(fenetre).cgPath))
    }
}

/// Arc de centre `(8, 7.2)` et de rayon `4.3`. Il ne colle pas à la capsule :
/// l'espace entre les deux fait partie du dessin.
private nonisolated struct Arceau: Shape {
    var angleDebut: Double
    var angleFin: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(angleDebut, angleFin) }
        set {
            angleDebut = newValue.first
            angleFin = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let e = Corps.echelle(rect)
        var trace = Path()
        trace.addArc(
            center: CGPoint(x: 8 * e, y: 7.2 * e),
            radius: 4.3 * e,
            startAngle: .degrees(angleDebut),
            endAngle: .degrees(angleFin),
            clockwise: false
        )
        return trace
    }
}

/// `rect x=7.35 y=11.5 w=1.3 h=2.5 rx=0.65`, dans l'axe. Un pied qui flotte,
/// détaché, lit comme un glyphe cassé — il reste donc à sa place dans les
/// quatre états, y compris quand l'arceau balaie.
private nonisolated struct Pied: Shape {
    func path(in rect: CGRect) -> Path {
        let e = Corps.echelle(rect)
        return Path(
            roundedRect: CGRect(x: 7.35 * e, y: 11.5 * e, width: 1.3 * e, height: 2.5 * e),
            cornerRadius: 0.65 * e
        )
    }
}

private nonisolated enum Corps {
    static func echelle(_ rect: CGRect) -> CGFloat { min(rect.width, rect.height) / 16 }

    static func rect(dans rect: CGRect) -> CGRect {
        let e = echelle(rect)
        return CGRect(x: 6.2 * e, y: 1.6 * e, width: 3.6 * e, height: 7.6 * e)
    }
}

#Preview("Les quatre états") {
    HStack(spacing: 24) {
        ForEach(DictationState.allCases, id: \.self) { etat in
            VStack(spacing: 8) {
                VoxGlyph(etat: etat, taille: 40)
                Text(etat.rawValue).font(.system(size: 11))
            }
        }
    }
    .padding(24)
}
