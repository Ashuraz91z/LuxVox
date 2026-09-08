//
//  MoteurTranscription.swift
//  Lux Vox
//

import AVFoundation
import Foundation

/// Où en est le modèle de transcription sur cette machine.
///
/// Le natif d'Apple ne transporte aucun modèle dans le `.dmg` : l'OS l'installe
/// au premier lancement. Il n'y a pas de mode dégradé en dessous — tant que
/// l'état n'est pas `.pret`, l'app ne transcrit rien, et doit le dire.
nonisolated enum EtatModele: Equatable, Sendable {
    /// Le moteur n'existe pas sur cette machine, ou la langue n'est pas servie.
    case indisponible(raison: String)
    /// Le modèle n'est pas là. Il faut une connexion, une fois.
    case aInstaller
    /// Installation en cours, progression de 0 à 1.
    case installation(Double)
    /// Prêt, et désormais utilisable hors ligne.
    case pret

    var estPret: Bool { self == .pret }
}

nonisolated enum ErreurTranscription: Error, Equatable {
    case modeleAbsent
    case langueNonSupportee(String)
    case moteurIndisponible
}

/// Un tampon audio qui franchit une frontière d'isolation.
///
/// `AVAudioPCMBuffer` est une classe non `Sendable`, et le mode Swift 6 refuse
/// à juste titre de la laisser traverser. Ici la propriété est réellement
/// transférée : le tampon est fabriqué par le tap audio, poussé une fois, et
/// plus jamais touché par le producteur. C'est ce transfert unique — et lui
/// seul — que ce `@unchecked` documente.
nonisolated struct TamponAudio: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

/// Le moteur de transcription, derrière une abstraction (décision *a* du
/// cahier des charges).
///
/// Une seule implémentation existe aujourd'hui, `SpeechTranscriberMoteur`, qui
/// s'appuie sur le moteur local d'Apple. L'abstraction n'est pas gratuite pour
/// autant : c'est elle qui permettra de poser WhisperKit à côté et de les
/// départager sur des chiffres, sans toucher au reste de l'app.
protocol MoteurTranscription: Sendable {
    /// Pour le banc d'essai et les journaux.
    static var nom: String { get }

    /// Le format que ce moteur préfère recevoir. L'audio du micro y sera
    /// converti.
    func formatAttendu() async -> AVAudioFormat?

    /// Charge ce qui doit l'être avant la première dictée. Sans ce
    /// préchauffage, la première transcription paie seule le prix du démarrage
    /// et fait sauter le budget de 2 secondes.
    func prechauffe() async throws

    /// Ouvre une session de dictée.
    func ouvreSession() async throws -> any SessionTranscription
}

/// Une dictée en cours. L'audio se pousse au fil de l'eau, le texte se récupère
/// à la fin.
protocol SessionTranscription: Sendable {
    func pousse(_ tampon: TamponAudio) async
    /// Ferme l'entrée et rend le texte transcrit, brut de moteur.
    func termine() async throws -> String
    /// Referme tout sans rien produire.
    func annule() async
}
