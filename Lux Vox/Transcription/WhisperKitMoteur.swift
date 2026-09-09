//
//  WhisperKitMoteur.swift
//  Lux Vox
//

import AVFoundation
import Foundation
import WhisperKit
import os

/// Le moteur WhisperKit, avec son modèle installé au premier lancement.
///
/// Le modèle ne voyage pas dans le `.dmg` : l'app est légère, et récupère le
/// modèle une fois, à la première ouverture. Il est ensuite rangé dans
/// *Application Support*, où — contrairement aux modèles du moteur d'Apple —
/// **macOS ne peut pas le purger**. Une fois installé, plus rien ne sort de la
/// machine.
actor WhisperKitMoteur: MoteurTranscription {

    static let nom = "WhisperKit (large-v3)"

    /// La variante publiée par Argmax, et le dépôt d'où elle vient.
    ///
    /// `large-v3` quantifié à 626 Mo, et non le `base` de 150 Mo qu'évoquait le
    /// cahier : mesuré sur des phrases de développement, `base` écrivait
    /// « poule request », « diboguer » et « bilb » là où `large-v3` rend « pull
    /// request », « debugger » et « build ». Le surcoût de téléchargement est
    /// payé une fois ; l'erreur de transcription, à chaque dictée.
    ///
    /// C'est aussi le modèle que WhisperKit recommande de lui-même pour une
    /// machine Apple Silicon.
    private nonisolated static let variante = "openai_whisper-large-v3-v20240930_626MB"
    private nonisolated static let depot = "argmaxinc/whisperkit-coreml"

    private let journal = Logger(subsystem: "lux-audere.Lux-Vox", category: "whisper")
    private var pipeline: WhisperKit?

    // MARK: - Emplacement du modèle

    /// La racine des téléchargements, sous *Application Support*.
    ///
    /// Ni le cache ni les Documents : un cache peut être vidé par le système,
    /// et 143 Mo n'ont rien à faire dans les documents de l'utilisateur.
    nonisolated static var racine: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Lux Vox", isDirectory: true)
    }

    /// Le dossier du modèle, selon l'arborescence que WhisperKit reproduit.
    nonisolated static var dossierModele: URL? {
        racine?
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(depot, isDirectory: true)
            .appendingPathComponent(variante, isDirectory: true)
    }

    /// Le modèle est présent si son décodeur l'est : c'est le fichier lourd,
    /// donc le dernier arrivé d'un téléchargement complet.
    nonisolated static func etat() -> EtatModele {
        guard let dossier = dossierModele else {
            return .indisponible(raison: "Dossier de données inaccessible.")
        }
        let decodeur = dossier
            .appendingPathComponent("TextDecoder.mlmodelc/weights/weight.bin")
        return FileManager.default.fileExists(atPath: decodeur.path) ? .pret : .aInstaller
    }

    /// Télécharge le modèle. Une seule fois, à la première ouverture.
    nonisolated static func installe(
        progression: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let racine else { throw ErreurTranscription.modeleAbsent }
        try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)

        _ = try await WhisperKit.download(
            variant: variante,
            downloadBase: racine,
            from: depot,
            progressCallback: { avancement in
                progression(avancement.fractionCompleted)
            }
        )
        progression(1)
    }

    // MARK: - MoteurTranscription

    /// Aucun format imposé : la conversion vers le 16 kHz de Whisper se fait à
    /// la fin de la dictée, sur l'audio complet.
    func formatAttendu() async -> AVAudioFormat? { nil }

    func prechauffe() async throws {
        _ = try await pipelinePrete()
    }

    func ouvreSession() async throws -> any SessionTranscription {
        // Le pipeline reste ici : `WhisperKit` n'est pas `Sendable`, et le
        // faire traverser vers la session serait précisément l'accès concurrent
        // que le mode Swift 6 est là pour refuser. La session délègue.
        _ = try await pipelinePrete()
        return await SessionWhisper(moteur: self)
    }

    /// Transcrit un bloc d'échantillons 16 kHz mono. Seuls des `[Float]`
    /// franchissent la frontière de l'acteur.
    func transcris(_ echantillons: [Float]) async throws -> String {
        let pipeline = try await pipelinePrete()
        let resultats = await pipeline.transcribe(
            audioArrays: [echantillons],
            decodeOptions: DecodingOptions(language: "fr")
        )
        return resultats
            .compactMap { $0 }
            .flatMap { $0 }
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Le premier chargement compile le modèle pour le Neural Engine et prend
    /// plus d'une minute ; les suivants quelques secondes. D'où le préchauffage
    /// au lancement, hors du chemin de la première dictée.
    private func pipelinePrete() async throws -> WhisperKit {
        if let pipeline { return pipeline }
        guard let racine = Self.racine, Self.etat().estPret else {
            throw ErreurTranscription.modeleAbsent
        }

        let depart = ContinuousClock.now
        var config = WhisperKitConfig(model: Self.variante)
        config.downloadBase = racine
        config.modelRepo = Self.depot
        config.prewarm = true

        let pret = try await WhisperKit(config)
        pipeline = pret
        journal.info("modèle chargé en \((ContinuousClock.now - depart).description, privacy: .public)")
        return pret
    }
}

/// Une dictée en cours côté Whisper.
///
/// Whisper ne consomme pas un flux continu comme le moteur d'Apple : il
/// transcrit un bloc d'échantillons. On accumule donc l'audio brut, et on le
/// rééchantillonne d'un seul coup à la fin — ce qui évite au passage les pertes
/// aux jointures qu'une conversion tampon par tampon provoque.
private actor SessionWhisper: SessionTranscription {

    private let moteur: WhisperKitMoteur
    private var tampons: [AVAudioPCMBuffer] = []
    private var annulee = false

    /// `async` : la cible compile en `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
    /// qui isolerait un initialiseur synchrone sur l'UI et le rendrait
    /// inappelable depuis le moteur.
    init(moteur: WhisperKitMoteur) async {
        self.moteur = moteur
    }

    func pousse(_ tampon: TamponAudio) async {
        guard !annulee else { return }
        tampons.append(tampon.buffer)
    }

    func termine() async throws -> String {
        guard !annulee,
              let echantillons = Self.enSeizeKiloHertz(tampons),
              !echantillons.isEmpty else { return "" }
        tampons = []
        return try await moteur.transcris(echantillons)
    }

    func annule() async {
        annulee = true
        tampons = []
    }

    /// Concatène les tampons et les rééchantillonne en 16 kHz mono.
    private nonisolated static func enSeizeKiloHertz(_ tampons: [AVAudioPCMBuffer]) -> [Float]? {
        guard let premier = tampons.first else { return nil }

        guard let cible = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ), let convertisseur = AVAudioConverter(from: premier.format, to: cible) else { return nil }

        var sortie: [Float] = []

        // Un seul convertisseur pour toute la dictée : c'est lui qui garde
        // l'état du rééchantillonnage d'un tampon à l'autre.
        for entree in tampons {
            let capacite = AVAudioFrameCount(
                Double(entree.frameLength) * 16_000 / entree.format.sampleRate
            ) + 1024
            guard let bloc = AVAudioPCMBuffer(pcmFormat: cible, frameCapacity: capacite) else { continue }

            var fourni = false
            var erreur: NSError?
            convertisseur.convert(to: bloc, error: &erreur) { _, statut in
                if fourni {
                    statut.pointee = .noDataNow
                    return nil
                }
                fourni = true
                statut.pointee = .haveData
                return entree
            }

            guard erreur == nil, let canal = bloc.floatChannelData?[0] else { continue }
            sortie.append(contentsOf: UnsafeBufferPointer(start: canal, count: Int(bloc.frameLength)))
        }
        return sortie
    }
}
