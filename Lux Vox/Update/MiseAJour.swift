//
//  MiseAJour.swift
//  Lux Vox
//

import AppKit
import Observation
import os

/// Cherche s'il existe une version plus récente, et la télécharge.
///
/// **Elle interroge GitHub directement, et pas lux-audere.com.** Le site est
/// trois pages statiques ; lui faire porter un service, c'est lui donner un
/// serveur à tenir, une dépendance PHP et des requêtes à voir passer. GitHub
/// héberge déjà les fichiers et publie déjà la liste — autant s'adresser à
/// l'endroit où l'information est vraie.
///
/// **Ce qui part de la machine :** une requête GET vers l'API publique de
/// GitHub, toutes les six heures. Elle ne porte ni identifiant, ni version,
/// ni rien qui distingue une machine d'une autre — c'est la même requête pour
/// tout le monde, celle que n'importe quel navigateur ferait en ouvrant la
/// page des releases.
///
/// **Ce qu'elle ne fait pas :** installer. Le remplacement du bundle en place
/// demande une signature *Developer ID* et une notarisation, que l'app n'a
/// pas encore — voir `.pret` plus bas. En attendant, elle amène le `.dmg` et
/// ouvre sa fenêtre ; le dernier geste reste à l'utilisateur.
@MainActor
@Observable
final class MiseAJour {

    // MARK: - La version

    /// Un numéro de version comparable, tolérant sur la forme.
    ///
    /// Les étiquettes du dépôt ne sont pas régulières : `0.1` d'un côté,
    /// `v0.2.0` de l'autre. Un comparateur qui exigerait trois nombres et pas
    /// de préfixe raterait la moitié des releases — et raterait en silence,
    /// puisqu'une version illisible se contente de disparaître de la liste.
    nonisolated struct Version: Comparable, CustomStringConvertible {
        let composants: [Int]

        init?(_ texte: String) {
            var brut = texte.trimmingCharacters(in: .whitespacesAndNewlines)
            if brut.first == "v" || brut.first == "V" { brut.removeFirst() }

            let morceaux = brut.split(separator: ".", omittingEmptySubsequences: false)
            guard !morceaux.isEmpty else { return nil }

            var nombres: [Int] = []
            for morceau in morceaux {
                guard let nombre = Int(morceau), nombre >= 0 else { return nil }
                nombres.append(nombre)
            }
            composants = nombres
        }

        /// Les manquants valent zéro, des deux côtés : sans ça `0.1` et
        /// `0.1.0` ne seraient pas la même version, et `0.2` passerait pour
        /// plus vieille que `0.2.0`.
        private static func aligne(_ a: Version, _ b: Version) -> [(Int, Int)] {
            let taille = max(a.composants.count, b.composants.count)
            return (0..<taille).map { rang in
                (rang < a.composants.count ? a.composants[rang] : 0,
                 rang < b.composants.count ? b.composants[rang] : 0)
            }
        }

        static func < (a: Version, b: Version) -> Bool {
            for (x, y) in aligne(a, b) where x != y { return x < y }
            return false
        }

        static func == (a: Version, b: Version) -> Bool {
            aligne(a, b).allSatisfy { $0 == $1 }
        }

        var description: String {
            composants.map(String.init).joined(separator: ".")
        }
    }

    // MARK: - L'état

    enum Etat {
        case inconnu
        case verification
        case aJour
        case disponible(Version)
        case telechargement(Version)
        /// Le `.dmg` est dans les téléchargements et sa fenêtre est ouverte.
        case pret(Version, URL)
        case echec(String)
    }

    private(set) var etat: Etat = .inconnu

    /// La version qui tourne, telle que l'a inscrite `MARKETING_VERSION`.
    let courante: Version

    private var lien: URL?
    private var minuterie: Timer?
    private let journal = Logger(subsystem: "lux-audere.Lux-Vox", category: "mise-a-jour")

    /// La liste complète, et non `/releases/latest`.
    ///
    /// `latest` ignore tout ce qui est coché « pre-release », et **toutes** les
    /// releases de Lux Vox le sont aujourd'hui — l'endpoint répond 404 sur ce
    /// dépôt. Lire la liste et prendre le plus grand numéro marche dans les
    /// deux cas ; le prix est qu'une préversion sera proposée comme une autre.
    /// Le jour où il faudra un canal stable, c'est ici que ça se filtre.
    private nonisolated static let sourceDesReleases = URL(
        string: "https://api.github.com/repos/Ashuraz91z/LuxVox/releases"
    )!

    init() {
        let inscrite = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        courante = Version(inscrite ?? "") ?? Version("0.0.0")!
    }

    func demarre() {
        verifie()
        // Lux Vox est un agent : il tourne des jours d'affilée sans jamais
        // être relancé. Sans ce réveil, une machine qu'on n'éteint pas
        // n'apprendrait jamais qu'une version est sortie.
        minuterie = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.verifie() }
        }
    }

    // MARK: - La vérification

    func verifie() {
        if case .telechargement = etat { return }
        etat = .verification

        Task {
            do {
                let (donnees, reponse) = try await Self.session.data(for: Self.requete())
                let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200 else {
                    // 403 sans corps, c'est le plafond de l'API publique :
                    // soixante requêtes par heure et par adresse. On ne le
                    // dit pas autrement qu'en ne disant rien.
                    throw Panne.reponse(code)
                }

                let decodeur = JSONDecoder()
                decodeur.keyDecodingStrategy = .convertFromSnakeCase
                let releases = try decodeur.decode([Release].self, from: donnees)

                guard let meilleure = Self.plusRecente(parmi: releases) else {
                    throw Panne.aucuneRelease
                }

                guard meilleure.version > courante else {
                    lien = nil
                    etat = .aJour
                    return
                }

                lien = meilleure.dmg
                etat = .disponible(meilleure.version)
            } catch {
                journal.debug("vérification impossible : \(error.localizedDescription, privacy: .public)")
                etat = .echec("Impossible de joindre GitHub.")
            }
        }
    }

    /// La release au plus grand numéro qui porte un `.dmg`.
    ///
    /// Une release sans `.dmg` n'est pas une mise à jour : elle existe, mais
    /// il n'y a rien à en télécharger. La proposer mènerait à un bouton qui
    /// échoue.
    nonisolated static func plusRecente(parmi releases: [Release]) -> (version: Version, dmg: URL)? {
        releases
            .filter { !$0.draft }
            .compactMap { release -> (version: Version, dmg: URL)? in
                guard let version = Version(release.tagName),
                      let dmg = release.assets.first(where: {
                          $0.name.lowercased().hasSuffix(".dmg")
                      })
                else { return nil }
                return (version, dmg.browserDownloadUrl)
            }
            .max { $0.version < $1.version }
    }

    // MARK: - Le téléchargement

    func telecharge() {
        guard case .disponible(let version) = etat, let source = lien else { return }
        etat = .telechargement(version)

        Task {
            do {
                let (temporaire, reponse) = try await Self.session.download(from: source)
                let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200 else { throw Panne.reponse(code) }

                let destination = try Self.range(temporaire, sous: source.lastPathComponent)
                etat = .pret(version, destination)

                // Monter l'image dans la foulée : le geste attendu est de
                // glisser l'app, et il n'y a aucune raison de demander un
                // second clic pour ouvrir une fenêtre qu'on vient de
                // télécharger exprès.
                NSWorkspace.shared.open(destination)
            } catch {
                journal.error("téléchargement impossible : \(error.localizedDescription, privacy: .public)")
                etat = .echec("Le téléchargement a échoué.")
            }
        }
    }

    /// Range le fichier temporaire dans les téléchargements sans écraser ce
    /// qui s'y trouve déjà — quelqu'un peut très bien avoir pris le `.dmg`
    /// à la main la veille.
    ///
    /// Le dossier est un paramètre pour que le test n'ait pas à écrire dans
    /// les vrais Téléchargements de qui lance la suite.
    nonisolated static func range(
        _ temporaire: URL,
        sous nom: String,
        dans dossierChoisi: URL? = nil
    ) throws -> URL {
        let fichiers = FileManager.default
        let dossier = try dossierChoisi ?? fichiers.url(
            for: .downloadsDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )

        let base = (nom as NSString).deletingPathExtension
        let extension_ = (nom as NSString).pathExtension
        var destination = dossier.appendingPathComponent(nom)
        var rang = 1
        while fichiers.fileExists(atPath: destination.path) {
            destination = dossier.appendingPathComponent("\(base) (\(rang)).\(extension_)")
            rang += 1
        }

        try fichiers.moveItem(at: temporaire, to: destination)
        return destination
    }

    func montreDansLeFinder() {
        guard case .pret(_, let fichier) = etat else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fichier])
    }

    // MARK: - Le réseau

    /// L'API refuse les requêtes sans agent, et la version de l'API se
    /// demande explicitement — sans quoi GitHub sert celle du jour, qui peut
    /// changer sous nos pieds.
    private nonisolated static func requete() -> URLRequest {
        var requete = URLRequest(url: sourceDesReleases)
        requete.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        requete.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        requete.setValue("Lux Vox", forHTTPHeaderField: "User-Agent")
        return requete
    }

    private nonisolated static let session: URLSession = {
        let reglages = URLSessionConfiguration.ephemeral
        reglages.timeoutIntervalForRequest = 15
        reglages.timeoutIntervalForResource = 300
        reglages.waitsForConnectivity = false
        return URLSession(configuration: reglages)
    }()

    // MARK: - Ce que GitHub renvoie

    nonisolated struct Release: Decodable {
        let tagName: String
        let draft: Bool
        let assets: [Asset]

        nonisolated struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
    }

    private enum Panne: Error {
        case reponse(Int)
        case aucuneRelease
    }
}
