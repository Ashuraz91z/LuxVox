//
//  fond-dmg.swift
//  Lux Vox — le fond de la fenêtre du DMG
//
//      xcrun swift Scripts/fond-dmg.swift [dossier-de-sortie]
//
//  Sort deux PNG — `fond.png` (1×) et `fond@2x.png` — que `dmg.sh` assemble
//  en un TIFF multi-résolution, plus un `cotes.sh` qu'il lit pour poser la
//  fenêtre et les icônes. Ce dernier existe pour que les cotes n'aient qu'un
//  seul domicile : Finder ne redimensionne pas une image de fond, il la pose,
//  donc la fenêtre et le dessin doivent s'accorder au pixel. Recopier les
//  nombres dans les deux scripts, c'est attendre le jour où l'un des deux
//  bouge seul.
//
//  Registre produit (DA §2.1) : crème et vert forêt, l'ardoise pour l'accent.
//  Pas d'anneau, pas de faisceau — un produit ne porte pas le logo de la
//  maison (§2.3), et cette fenêtre ne contient que du Lux Vox.
//
//  ── Pourquoi la légende répète ce que disent déjà les étiquettes ──
//
//  Finder dessine le nom sous chaque icône dans la couleur du thème de
//  l'utilisateur : noir en clair, blanc en sombre. Le fond, lui, est fixe.
//  Sur ce crème, les étiquettes d'un utilisateur en thème sombre sont donc
//  presque illisibles, et aucun choix de fond ne répare les deux thèmes à la
//  fois — un fond sombre inverserait simplement le problème.
//
//  D'où la règle de composition : **les étiquettes ne portent aucune
//  information.** La flèche porte le geste, la légende porte les mots, les
//  deux icônes se reconnaissent à leur forme. Si Finder les efface, la
//  fenêtre se comprend encore.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette
//
// Les mêmes jetons que `LuxColor.swift` et que la variante claire de l'icône.

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

enum Fond {
    static let hautDeCiel = srgb(0xFBF9F6)
    static let basDeCiel = srgb(0xF1ECE4)
    /// L'ardoise — l'accent propre à Lux Vox, la seule teinte froide de la
    /// palette Lux.
    static let ardoise: UInt32 = 0x4A7C8C
    static let texte = srgb(0x5B6B5E)
}

// MARK: - Cotes
//
// Un seul jeu de nombres, écrit ici parce que c'est ici qu'on dessine, et
// relu par `dmg.sh` via `cotes.sh`.

enum Scene {
    static let largeur: CGFloat = 620
    static let hauteur: CGFloat = 360

    /// Repères en coordonnées Finder — origine en haut à gauche.
    static let icone: CGFloat = 128
    static let axeDesIcones: CGFloat = 158
    static let xApp: CGFloat = 170
    static let xApplications: CGFloat = 450

    /// Ligne de la légende, également depuis le haut.
    static let axeDeLaLegende: CGFloat = 296
}

// MARK: - Dessin

func dessine(dans context: CGContext) {
    let cadre = CGRect(x: 0, y: 0, width: Scene.largeur, height: Scene.hauteur)
    let espace = CGColorSpace(name: CGColorSpace.sRGB)!

    // ── Le ciel ───────────────────────────────────────────────────
    let ciel = CGGradient(
        colorsSpace: espace,
        colors: [Fond.hautDeCiel, Fond.basDeCiel] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        ciel,
        start: CGPoint(x: cadre.midX, y: cadre.maxY),
        end: CGPoint(x: cadre.midX, y: cadre.minY),
        options: []
    )

    // ── La levée ──────────────────────────────────────────────────
    //
    // Elle ne décore pas : elle désigne. Des deux icônes de la fenêtre, une
    // seule est le sujet — l'autre est une destination. La levée dit
    // laquelle sans ajouter une forme de plus.
    //
    // Blanche, et non pas ardoise : l'accent du produit posé en aplat très
    // dilué sur du crème ne donne pas une teinte, il donne un gris sale. Ce
    // qu'on veut ici n'est pas une couleur, c'est de la lumière.
    let centreApp = CGPoint(
        x: Scene.xApp,
        y: Scene.hauteur - Scene.axeDesIcones + 10
    )
    let levee = CGGradient(
        colorsSpace: espace,
        colors: [srgb(0xFFFFFF, 0.90), srgb(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        levee,
        startCenter: centreApp, startRadius: 0,
        endCenter: centreApp, endRadius: 200,
        options: []
    )

    // ── La flèche ─────────────────────────────────────────────────
    //
    // Trait à bouts ronds et chevron ouvert : la capsule est la primitive
    // de la DA, jusque dans une flèche.
    let y = Scene.hauteur - Scene.axeDesIcones
    let depart: CGFloat = 268
    let arrivee: CGFloat = 352
    let trait: CGFloat = 2.5

    context.setStrokeColor(srgb(Fond.ardoise, 0.55))
    context.setLineWidth(trait)
    context.setLineCap(.round)
    context.setLineJoin(.round)

    context.move(to: CGPoint(x: depart, y: y))
    context.addLine(to: CGPoint(x: arrivee - 7, y: y))
    context.strokePath()

    let pointe: CGFloat = 9
    context.move(to: CGPoint(x: arrivee - pointe, y: y + pointe * 0.8))
    context.addLine(to: CGPoint(x: arrivee, y: y))
    context.addLine(to: CGPoint(x: arrivee - pointe, y: y - pointe * 0.8))
    context.strokePath()

    // ── La légende ────────────────────────────────────────────────
    let ns = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns

    let paragraphe = NSMutableParagraphStyle()
    paragraphe.alignment = .center

    let legende = NSAttributedString(
        string: "Glissez Lux Vox dans Applications",
        attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: NSColor(cgColor: Fond.texte)!,
            .paragraphStyle: paragraphe,
            // La DA n'espace les capitales que sur la marque. Ici c'est du
            // texte courant : interlettrage normal.
            .kern: 0,
        ]
    )
    legende.draw(in: CGRect(
        x: 0,
        y: Scene.hauteur - Scene.axeDeLaLegende - 10,
        width: Scene.largeur,
        height: 22
    ))

    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Rendu

func rendu(echelle: CGFloat) -> CGImage {
    let context = CGContext(
        data: nil,
        width: Int(Scene.largeur * echelle),
        height: Int(Scene.hauteur * echelle),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    // Tout le dessin est en points : l'échelle ne se retrouve nulle part
    // ailleurs que sur cette ligne.
    context.scaleBy(x: echelle, y: echelle)

    dessine(dans: context)
    return context.makeImage()!
}

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
    print("  \(url.path)")
}

// MARK: - Sortie

let racine = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let sortie = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : racine.appendingPathComponent("A")

write(rendu(echelle: 1), to: sortie.appendingPathComponent("fond.png"))
write(rendu(echelle: 2), to: sortie.appendingPathComponent("fond@2x.png"))

let cotes = """
largeur=\(Int(Scene.largeur))
hauteur=\(Int(Scene.hauteur))
icone=\(Int(Scene.icone))
axe=\(Int(Scene.axeDesIcones))
x_app=\(Int(Scene.xApp))
x_applications=\(Int(Scene.xApplications))
"""
let fichier = sortie.appendingPathComponent("cotes.sh")
try! cotes.write(to: fichier, atomically: true, encoding: .utf8)
print("  \(fichier.path)")
