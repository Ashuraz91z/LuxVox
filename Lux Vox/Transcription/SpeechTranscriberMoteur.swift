//
//  SpeechTranscriberMoteur.swift
//  Lux Vox
//

import AVFoundation
import Foundation
import Speech
import os

/// Le moteur local d'Apple (`SpeechTranscriber`, macOS 26+).
///
/// Rien ne part sur le réseau pendant la dictée : l'API n'expose aucune notion
/// de serveur, contrairement à l'ancienne `SFSpeechRecognizer` et son
/// `requiresOnDeviceRecognition`. La seule fois où une connexion est nécessaire
/// est l'installation du modèle, une fois pour toutes.
actor SpeechTranscriberMoteur: MoteurTranscription {

    static let nom = "SpeechTranscriber (Apple)"

    /// Français forcé (§7 du cahier) : évite la latence et les erreurs de
    /// détection automatique.
    nonisolated static let langue = Locale(identifier: "fr_FR")

    private var formatCache: AVAudioFormat?

    // MARK: - Cycle du modèle

    /// La langue est-elle servie par ce moteur sur cette machine ?
    nonisolated static func langueServie() async -> Bool {
        guard SpeechTranscriber.isAvailable else { return false }
        return await SpeechTranscriber.supportedLocale(equivalentTo: langue) != nil
    }

    /// Où en est le modèle, sans rien télécharger.
    nonisolated static func etat() async -> EtatModele {
        guard SpeechTranscriber.isAvailable else {
            return .indisponible(raison: "Moteur de transcription absent de ce système.")
        }
        guard await SpeechTranscriber.supportedLocale(equivalentTo: langue) != nil else {
            return .indisponible(raison: "Le français n'est pas servi par ce moteur.")
        }

        // `AssetInventory.status` n'est pas une réponse fiable à « peut-on
        // transcrire ? » : sur une machine où tout est en place, il a rendu
        // `supported` puis `installed` d'un appel à l'autre, sans qu'aucun
        // téléchargement n'ait eu lieu entre les deux. S'y fier faisait refuser
        // toutes les dictées.
        //
        // La question qui décide est celle-ci : reste-t-il quelque chose à
        // installer ? Quand le système n'a aucune requête d'installation à
        // fournir, c'est qu'il n'y a rien à attendre.
        do {
            if try await AssetInventory.assetInstallationRequest(supporting: [module()]) != nil {
                return .aInstaller
            }
            return .pret
        } catch {
            return .aInstaller
        }
    }

    /// Télécharge et installe le modèle français.
    ///
    /// `reserve(locale:)` n'est pas cosmétique : sans réservation, le système
    /// est libre de purger l'asset pour récupérer de l'espace disque, et la
    /// dictée s'arrêterait un matin sans que rien n'ait changé — en exigeant
    /// une connexion pour repartir.
    nonisolated static func installe(progression: @escaping @Sendable (Double) -> Void) async throws {
        guard let requete = try await AssetInventory.assetInstallationRequest(supporting: [module()]) else {
            // Rien à installer : le modèle est déjà là.
            _ = try? await AssetInventory.reserve(locale: langue)
            return
        }

        let observation = requete.progress.observe(\.fractionCompleted) { avancement, _ in
            progression(avancement.fractionCompleted)
        }
        defer { observation.invalidate() }

        try await requete.downloadAndInstall()
        _ = try? await AssetInventory.reserve(locale: langue)
        progression(1)
    }

    private nonisolated static func module() -> SpeechTranscriber {
        SpeechTranscriber(locale: langue, preset: .progressiveTranscription)
    }

    // MARK: - MoteurTranscription

    func formatAttendu() async -> AVAudioFormat? {
        if let formatCache { return formatCache }
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [Self.module()])
        formatCache = format
        return format
    }

    /// Résout le format et laisse l'OS charger ce qu'il doit charger, pour que
    /// la première dictée ne paie pas seule le démarrage.
    func prechauffe() async throws {
        guard await Self.etat().estPret else { throw ErreurTranscription.modeleAbsent }
        _ = await formatAttendu()
    }

    func ouvreSession() async throws -> any SessionTranscription {
        guard await Self.etat().estPret else { throw ErreurTranscription.modeleAbsent }

        let transcripteur = Self.module()
        let analyseur = SpeechAnalyzer(modules: [transcripteur])
        let convertisseur = try await AnalyzerInputConverter.converter(compatibleWith: [transcripteur])
        let (flux, alimentation) = AsyncStream<AnalyzerInput>.makeStream()

        try await analyseur.prepareToAnalyze(in: await formatAttendu())
        try await analyseur.start(inputSequence: flux)

        return await SessionSpeech(
            analyseur: analyseur,
            transcripteur: transcripteur,
            alimentation: alimentation,
            convertisseur: convertisseur
        )
    }
}

/// Une dictée en cours côté Apple.
///
/// Le texte se collecte au fil des résultats plutôt qu'en une fois à la fin :
/// le préréglage `progressiveTranscription` émet des résultats partiels, et
/// seul le dernier de chaque plage est définitif.
private actor SessionSpeech: SessionTranscription {

    private let journal = Logger(subsystem: "lux-audere.Lux-Vox", category: "transcription")
    private let analyseur: SpeechAnalyzer
    private let transcripteur: SpeechTranscriber
    private let alimentation: AsyncStream<AnalyzerInput>.Continuation
    private let convertisseur: AnalyzerInputConverter
    private var collecte: Task<String, Error>?
    private var tamponsPousses = 0

    /// Initialiseur `async` : la cible compile en
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, qui isolerait un
    /// initialiseur synchrone sur l'UI et le rendrait inappelable depuis le
    /// moteur. La variante asynchrone est isolée à l'acteur lui-même.
    init(
        analyseur: SpeechAnalyzer,
        transcripteur: SpeechTranscriber,
        alimentation: AsyncStream<AnalyzerInput>.Continuation,
        convertisseur: AnalyzerInputConverter
    ) async {
        self.analyseur = analyseur
        self.transcripteur = transcripteur
        self.alimentation = alimentation
        self.convertisseur = convertisseur

        // La collecte démarre avant le premier tampon : les résultats sont un
        // flux, et ce qui est émis avant qu'on écoute est perdu.
        let resultats = transcripteur.results
        collecte = Task {
            var texte = ""
            for try await resultat in resultats {
                // `progressiveTranscription` émet des résultats volatils : des
                // reprises de plus en plus longues de la même phrase. Les
                // concaténer donne un texte en escalier — « Il / Il faut / Il
                // faut que… ». Seuls les résultats finaux comptent.
                guard resultat.isFinal else { continue }
                texte += String(resultat.text.characters)
            }
            return texte
        }
    }

    /// Le rééchantillonnage vers le format du moteur est fait par
    /// `AnalyzerInputConverter`, qui gère les jointures entre tampons — un
    /// tampon d'entrée peut donner zéro, une ou plusieurs entrées.
    func pousse(_ tampon: TamponAudio) async {
        do {
            for entree in try convertisseur.convert(tampon.buffer, at: nil) {
                alimentation.yield(entree)
                tamponsPousses += 1
            }
        } catch {
            journal.error("conversion refusée : \(error.localizedDescription, privacy: .public)")
        }
    }

    func termine() async throws -> String {
        for entree in (try? convertisseur.flush()) ?? [] {
            alimentation.yield(entree)
        }
        alimentation.finish()
        journal.info("fin de dictée, \(self.tamponsPousses, privacy: .public) entrées poussées")
        try await analyseur.finalizeAndFinishThroughEndOfInput()
        let texte = try await collecte?.value ?? ""
        journal.info("texte brut : \(texte.count, privacy: .public) caractères")
        return texte
    }

    func annule() async {
        alimentation.finish()
        collecte?.cancel()
        await analyseur.cancelAndFinishNow()
    }
}
