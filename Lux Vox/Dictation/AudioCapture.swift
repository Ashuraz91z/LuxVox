//
//  AudioCapture.swift
//  Lux Vox
//

import AVFoundation
import os

/// La capture micro, reprise du socle de `Lux Calendar/Services/DictationService.swift`.
///
/// Pas de session audio ici : `AVAudioSession` n'existe pas sur macOS, c'est la
/// seule pièce du socle iOS qui ne se transpose pas.
@MainActor
final class AudioCapture {

    private let journal = Logger(subsystem: "lux-audere.Lux-Vox", category: "audio")
    private let moteur = AVAudioEngine()
    private var actif = false

    // MARK: - Permission

    static var permissionAccordee: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var permissionRefusee: Bool {
        let statut = AVCaptureDevice.authorizationStatus(for: .audio)
        return statut == .denied || statut == .restricted
    }

    @discardableResult
    static func demandePermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: - Capture

    /// Ouvre le micro et pousse les tampons **bruts**.
    ///
    /// Aucun rééchantillonnage ici : convertir un flux 48 kHz vers 16 kHz avec
    /// un `AVAudioConverter` alimenté tampon par tampon perd des échantillons
    /// aux jointures. C'est au moteur de convertir, avec l'outil que son
    /// framework fournit pour ça.
    func demarre(
        recevoir: @escaping @Sendable (TamponAudio) -> Void,
        niveaux: @escaping @Sendable ([Float]) -> Void = { _ in }
    ) throws {
        guard !actif else { return }

        let entree = moteur.inputNode
        let format = entree.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            // Un périphérique d'entrée absent ou muet donne un format à zéro,
            // et le tap échouerait plus loin sans rien dire.
            throw ErreurCapture.aucuneEntree
        }

        journal.info("micro: \(format.sampleRate, privacy: .public) Hz, \(format.channelCount, privacy: .public) canal/aux")

        try Self.poseLeTap(sur: entree, format: format) { tampon in
            niveaux(Self.mesure(tampon))
            recevoir(TamponAudio(buffer: tampon))
        }

        moteur.prepare()
        do {
            try moteur.start()
        } catch {
            entree.removeTap(onBus: 0)
            throw error
        }
        actif = true
    }

    func arrete() {
        guard actif else { return }
        moteur.stop()
        moteur.inputNode.removeTap(onBus: 0)
        actif = false
    }

    /// Branche le micro.
    ///
    /// On utilise le tap de macOS 27 — celui qui signale ses échecs au lieu de
    /// les avaler —, et il faut savoir sous quelle forme : l'en-tête le marque
    /// `NS_REFINED_FOR_SWIFT` sans qu'Apple ait livré l'habillage Swift
    /// correspondant. Il ne s'atteint donc que sous le nom `__installTap`, et
    /// son paramètre `error:` survit à l'import sous la forme d'un `()`
    /// fantôme, alors que l'erreur remonte bien par `throws`.
    ///
    /// C'est laid et c'est volontaire : l'ancienne signature est dépréciée
    /// depuis macOS 27. Si une mise à jour d'Xcode casse la compilation, c'est
    /// ici, et la correction est de retirer `error: ()`.
    ///
    /// La taille de tampon doit tenir dans la plage acceptée (100–400 ms) :
    /// 8192 trames, soit ~170 ms à 48 kHz. Une valeur hors plage était tolérée
    /// en silence par l'ancienne API ; la nouvelle la refuse.
    private nonisolated static func poseLeTap(
        sur entree: AVAudioInputNode,
        format: AVAudioFormat,
        recevoir: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        try entree.__installTap(onBus: 0, bufferSize: 8192, format: format, error: ()) { tampon, _ in
            recevoir(tampon)
        }
    }
}

extension AudioCapture {

    /// Nombre de mesures tirées d'un même tampon.
    ///
    /// Un tampon couvre environ 170 ms : une seule valeur par tampon donnerait
    /// six points par seconde, trop peu pour une animation qui suit la voix.
    /// On le découpe donc en tranches.
    private nonisolated static let tranchesParTampon = 8

    /// Plage utile en décibels. En dessous, c'est du silence ; au-dessus, la
    /// voix sature l'affichage.
    private nonisolated static let planchederDecibels: Float = -55
    private nonisolated static let plafondDecibels: Float = -12

    /// Mesure l'énergie du tampon, tranche par tranche, sur une échelle
    /// décibel : c'est ainsi que l'oreille perçoit le volume, et une échelle
    /// linéaire écraserait tout le bas du registre.
    nonisolated static func mesure(_ tampon: AVAudioPCMBuffer) -> [Float] {
        guard let canal = tampon.floatChannelData?[0] else { return [] }
        let total = Int(tampon.frameLength)
        guard total > 0 else { return [] }

        let taille = max(1, total / tranchesParTampon)
        var sorties: [Float] = []
        sorties.reserveCapacity(tranchesParTampon)

        var debut = 0
        while debut < total {
            let fin = min(debut + taille, total)
            var somme: Float = 0
            for index in debut..<fin {
                let echantillon = canal[index]
                somme += echantillon * echantillon
            }
            let moyenne = (somme / Float(fin - debut)).squareRoot()
            sorties.append(normalise(moyenne))
            debut = fin
        }
        return sorties
    }

    private nonisolated static func normalise(_ amplitude: Float) -> Float {
        guard amplitude > 0 else { return 0 }
        let decibels = 20 * log10(amplitude)
        let part = (decibels - planchederDecibels) / (plafondDecibels - planchederDecibels)
        return min(max(part, 0), 1)
    }
}

nonisolated enum ErreurCapture: Error, CustomStringConvertible {
    case aucuneEntree

    var description: String {
        switch self {
        case .aucuneEntree: "Aucun périphérique d'entrée audio disponible."
        }
    }
}
