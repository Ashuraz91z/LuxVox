//
//  icon-generator.swift
//  Lux Vox — génération de l'icône
//
//  Script autonome, hors cible Xcode. Régénère tout le jeu d'icônes :
//
//      xcrun swift Scripts/icon-generator.swift
//
//  Il vit dans `Scripts/` et non dans `A/` : `A/` est hors dépôt, et un
//  générateur qu'un clone ne reçoit pas est une icône qu'on ne peut plus
//  refaire. Les planches, elles, restent dans `A/` — ce sont des sorties.
//
//  Le dessin est vectoriel et redessiné à chaque taille (pas de
//  redimensionnement), pour que les petites tailles restent nettes.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette
//
// Le squircle et le crème viennent de Calendar et de Md : c'est ce qui fait la
// famille. L'ardoise est propre à Lux Vox — la seule teinte froide de la
// palette, posée sur l'élément qui distingue le produit (DA §2.1).

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

struct Palette {
    var backgroundTop: CGColor
    var backgroundBottom: CGColor
    /// La capsule.
    var frame: CGColor
    /// Les barres.
    var voice: CGColor

    static let dark = Palette(
        backgroundTop: srgb(0x13291F),
        backgroundBottom: srgb(0x0B1A17),
        frame: srgb(0xD5ECCD),
        voice: srgb(0x8FB9C4)
    )

    static let light = Palette(
        backgroundTop: srgb(0xFBF9F6),
        backgroundBottom: srgb(0xF1ECE4),
        frame: srgb(0x94AD91),
        voice: srgb(0x4A7C8C)
    )
}

// MARK: - Formes

/// Superellipse — le carré arrondi d'Apple, que `CGPath(roundedRect:)` ne
/// sait pas produire (ses coins sont des arcs de cercle, visiblement plus durs).
func squircle(in rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2
    let b = rect.height / 2
    let steps = 1440

    for step in 0...steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = rect.midX + a * pow(abs(cosine), 2 / exponent) * (cosine < 0 ? -1 : 1)
        let y = rect.midY + b * pow(abs(sine), 2 / exponent) * (sine < 0 ? -1 : 1)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }

    path.closeSubpath()
    return path
}

/// Bouts entièrement arrondis, quel que soit le sens du rectangle.
///
/// Le rayon se prend sur le **petit** côté : `rect.height / 2` sur une barre
/// dressée dépasse la demi-largeur, et Core Graphics rend alors une lentille
/// pointue au lieu d'une capsule.
func capsulePath(_ rect: CGRect) -> CGPath {
    let rayon = min(rect.width, rect.height) / 2
    return CGPath(
        roundedRect: rect,
        cornerWidth: rayon,
        cornerHeight: rayon,
        transform: nil
    )
}

// MARK: - Dessin

/// La capsule et ses barres — ce que l'utilisateur voit tous les jours en bas
/// de l'écran, arrêté sur une image.
///
/// Md a quatre barres couchées, Vox les a dressées et enfermées : la parenté
/// se voit, la confusion non. Le contenant n'est pas décoratif — c'est lui qui
/// donne à l'icône sa silhouette reconnaissable à 16 pt, là où des barres
/// seules ne seraient qu'un peigne.
/// Trois niveaux de détail, et pas deux.
///
/// Un seul palier ne suffit pas : à 32 px l'anneau tient encore, à 16 il
/// mange tout l'intérieur et l'icône devient une tache. En dessous de 24 px
/// la capsule est donc retirée — il reste les barres, qui sont le sujet.
/// Perdre le contenant coûte moins cher que de perdre les deux.
enum Detail {
    case plein
    case simplifie
    case minimal

    init(taille: CGFloat) {
        self = taille < 24 ? .minimal : (taille < 64 ? .simplifie : .plein)
    }
}

func drawMark(in context: CGContext, side: CGFloat, center: CGPoint, palette: Palette, detail: Detail) {
    var hauteurMax: CGFloat

    switch detail {
    case .minimal:
        hauteurMax = side * 0.62

    case .plein, .simplifie:
        let plein = detail == .plein
        let largeur = side * (plein ? 0.66 : 0.76)
        let hauteur = side * (plein ? 0.325 : 0.42)
        let trait = side * (plein ? 0.028 : 0.040)

        let capsule = CGRect(
            x: center.x - largeur / 2,
            y: center.y - hauteur / 2,
            width: largeur,
            height: hauteur
        )
        // Le trait se centre sur le chemin : on rentre d'une demi-épaisseur
        // pour que le bord extérieur tombe exactement sur la cote.
        context.addPath(capsulePath(capsule.insetBy(dx: trait / 2, dy: trait / 2)))
        context.setStrokeColor(palette.frame)
        context.setLineWidth(trait)
        context.strokePath()

        hauteurMax = hauteur * (plein ? 0.58 : 0.62)
    }

    // Cinq barres seulement au grand format : en dessous elles se touchent.
    let parts: [CGFloat]
    let largeurBarre: CGFloat
    let espace: CGFloat

    switch detail {
    case .plein:
        parts = [0.38, 0.72, 1.0, 0.64, 0.44]
        largeurBarre = side * 0.044
        espace = side * 0.038
    case .simplifie:
        parts = [0.58, 1.0, 0.68]
        largeurBarre = side * 0.070
        espace = side * 0.080
    case .minimal:
        parts = [0.55, 1.0, 0.68]
        largeurBarre = side * 0.140
        espace = side * 0.130
    }

    let total = CGFloat(parts.count) * largeurBarre + CGFloat(parts.count - 1) * espace
    var x = center.x - total / 2

    for part in parts {
        // Jamais plus courte que large : au minimum la barre est un rond,
        // comme dans l'app au silence.
        let h = max(largeurBarre, hauteurMax * part)
        let rect = CGRect(x: x, y: center.y - h / 2, width: largeurBarre, height: h)
        context.addPath(capsulePath(rect))
        // Les basses s'effacent un peu : la crête porte le regard. À 16 px
        // aucune nuance ne survit, elles restent toutes pleines.
        let alpha = detail == .minimal ? 1 : 0.66 + 0.34 * part
        context.setFillColor(palette.voice.copy(alpha: alpha) ?? palette.voice)
        context.fillPath()
        x += largeurBarre + espace
    }
}

func makeIcon(size: CGFloat, palette: Palette) -> CGImage {
    let pixels = Int(size)
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("contexte impossible à créer") }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    // macOS attend le squircle détouré, avec sa marge et son ombre.
    let margin = size * 100 / 1024
    let side = size - 2 * margin
    let rect = CGRect(x: margin, y: margin, width: side, height: side)
    let shape = squircle(in: rect)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -side * 0.014),
        blur: side * 0.04,
        color: srgb(0x000000, 0.30)
    )
    context.addPath(shape)
    context.setFillColor(palette.backgroundBottom)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [palette.backgroundTop, palette.backgroundBottom] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: []
    )
    context.restoreGState()

    drawMark(
        in: context,
        side: side,
        center: CGPoint(x: rect.midX, y: rect.midY),
        palette: palette,
        detail: Detail(taille: size)
    )

    return context.makeImage()!
}

// MARK: - Écriture

func write(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { fatalError("écriture impossible : \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("  \(url.lastPathComponent)")
}

/// Planche de présentation : les deux variantes sur leur fond, plus la file
/// des petites tailles — c'est là que se jugent les choix de simplification.
func makeShowcase(size: CGFloat = 1254) -> CGImage {
    let pixels = Int(size)
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    context.setFillColor(srgb(0x091215))
    context.fill(CGRect(x: 0, y: size / 2, width: size, height: size / 2))
    context.setFillColor(srgb(0xFBF8F5))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size / 2))

    let iconSize = size * 0.42
    context.interpolationQuality = .high

    context.draw(makeIcon(size: 1024, palette: .dark), in: CGRect(
        x: (size - iconSize) / 2,
        y: size / 2 + (size / 2 - iconSize) / 2,
        width: iconSize, height: iconSize
    ))
    context.draw(makeIcon(size: 1024, palette: .light), in: CGRect(
        x: (size - iconSize) / 2,
        y: (size / 2 - iconSize) / 2,
        width: iconSize, height: iconSize
    ))

    // Les petites tailles au vrai pixel, sur les deux fonds.
    let petites: [CGFloat] = [16, 32, 64, 128]
    for (haut, palette) in [(true, Palette.dark), (false, Palette.light)] {
        var x = size * 0.06
        let y = haut ? size * 0.94 - 128 : size * 0.44 - 128
        for taille in petites {
            let image = makeIcon(size: taille, palette: palette)
            context.draw(image, in: CGRect(x: x, y: y + (128 - taille) / 2, width: taille, height: taille))
            x += taille + size * 0.03
        }
    }

    return context.makeImage()!
}

// MARK: - Sortie

let racine = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let planches = racine.appendingPathComponent("A")
let appIcon = racine.appendingPathComponent("Lux Vox/Assets.xcassets/AppIcon.appiconset")

print("planches (A/)")
write(makeIcon(size: 1024, palette: .dark), to: planches.appendingPathComponent("LuxVox-Icon-Dark-1024.png"))
write(makeIcon(size: 1024, palette: .light), to: planches.appendingPathComponent("LuxVox-Icon-Light-1024.png"))
write(makeShowcase(), to: planches.appendingPathComponent("LuxVox-Icon-Presentation.png"))

print("jeu d'icônes (AppIcon.appiconset)")
// Lux Vox est une app macOS seule : pas de variantes iOS claire/sombre/teintée.
let macSizes: [(String, CGFloat)] = [
    ("AppIcon-mac-16.png", 16),
    ("AppIcon-mac-16@2x.png", 32),
    ("AppIcon-mac-32.png", 32),
    ("AppIcon-mac-32@2x.png", 64),
    ("AppIcon-mac-128.png", 128),
    ("AppIcon-mac-128@2x.png", 256),
    ("AppIcon-mac-256.png", 256),
    ("AppIcon-mac-256@2x.png", 512),
    ("AppIcon-mac-512.png", 512),
    ("AppIcon-mac-512@2x.png", 1024),
]
for (name, size) in macSizes {
    write(makeIcon(size: size, palette: .dark), to: appIcon.appendingPathComponent(name))
}
