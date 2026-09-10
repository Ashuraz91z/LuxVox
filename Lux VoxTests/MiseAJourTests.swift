//
//  MiseAJourTests.swift
//  Lux VoxTests
//

import Foundation
import Testing
@testable import Lux_Vox

/// Deux choses qu'aucun essai à la main ne rattrape.
///
/// La comparaison de versions, d'abord : elle ne se voit pas. Une app qui se
/// croit à jour ne dit rien — elle ne montre pas d'erreur, elle ne fait
/// simplement plus rien, et personne ne s'en aperçoit avant plusieurs
/// versions.
///
/// La lecture de la réponse de GitHub, ensuite. Les noms de champs viennent
/// d'une API qui n'est pas la nôtre ; le seul endroit où on peut les fixer est
/// un test qui les écrit.
@Suite("Mise à jour")
struct MiseAJourTests {

    typealias Version = MiseAJour.Version

    // MARK: - Les numéros

    /// Les étiquettes du dépôt ne sont pas régulières : `0.1` d'un côté,
    /// `v0.2.0` de l'autre. Les deux doivent se lire.
    @Test(
        "Les étiquettes réelles du dépôt se lisent",
        arguments: [
            ("v0.2.0", [0, 2, 0]),
            ("0.1", [0, 1]),
            ("V1.0.0", [1, 0, 0]),
            ("  0.3.1  ", [0, 3, 1]),
        ]
    )
    func lecture(_ etiquette: String, _ attendu: [Int]) throws {
        #expect(try #require(Version(etiquette)).composants == attendu)
    }

    @Test(
        "Ce qui n'est pas un numéro est refusé",
        arguments: ["", "v", "0.2.0-beta", "latest", "0.x", "-1.0", "0..1"]
    )
    func refus(_ etiquette: String) {
        #expect(Version(etiquette) == nil)
    }

    /// Le cas qui casse une comparaison de chaînes : `"0.10" < "0.9"` est vrai
    /// pour du texte et faux pour des versions. C'est le bug qu'on ne voit
    /// qu'à la dixième release.
    @Test("0.10.0 vient après 0.9.0")
    func dizaines() throws {
        let neuf = try #require(Version("0.9.0"))
        let dix = try #require(Version("0.10.0"))
        #expect(neuf < dix)
        #expect(!(dix < neuf))
    }

    /// Les composants manquants valent zéro **des deux côtés**. Sans ça,
    /// `0.2` passerait pour plus récente que `0.2.0` et l'app proposerait
    /// indéfiniment une mise à jour vers elle-même.
    @Test(
        "Un composant absent vaut zéro",
        arguments: [("0.1", "0.1.0"), ("1", "1.0.0"), ("0.2.0", "0.2")]
    )
    func alignement(_ court: String, _ long: String) throws {
        let a = try #require(Version(court))
        let b = try #require(Version(long))
        #expect(a == b)
        #expect(!(a < b))
        #expect(!(b < a))
    }

    @Test("L'ordre général")
    func ordre() throws {
        let suite = try ["0.1", "0.1.1", "0.2.0", "0.10.0", "1.0.0"].map {
            try #require(Version($0))
        }
        #expect(suite == suite.sorted())
    }

    // MARK: - Ce que GitHub renvoie

    /// La forme réelle de la réponse, réduite aux champs qu'on lit. Les noms
    /// sont recopiés depuis l'API — c'est `convertFromSnakeCase` qui les
    /// transforme, et un champ renommé chez GitHub casserait ici.
    static let reponseGitHub = """
    [
      {
        "tag_name": "v0.2.0",
        "draft": false,
        "prerelease": true,
        "assets": [
          {
            "name": "LuxVox0.2.0.dmg",
            "browser_download_url": "https://github.com/Ashuraz91z/LuxVox/releases/download/v0.2.0/LuxVox0.2.0.dmg"
          }
        ]
      },
      {
        "tag_name": "0.1",
        "draft": false,
        "prerelease": true,
        "assets": [
          {
            "name": "LuxVox-0.1.0.dmg",
            "browser_download_url": "https://github.com/Ashuraz91z/LuxVox/releases/download/0.1/LuxVox-0.1.0.dmg"
          }
        ]
      }
    ]
    """

    static func decode(_ json: String) throws -> [MiseAJour.Release] {
        let decodeur = JSONDecoder()
        decodeur.keyDecodingStrategy = .convertFromSnakeCase
        return try decodeur.decode([MiseAJour.Release].self, from: Data(json.utf8))
    }

    @Test("La réponse réelle du dépôt donne 0.2.0 et son .dmg")
    func lectureDeLaReponse() throws {
        let releases = try Self.decode(Self.reponseGitHub)
        let trouvee = try #require(MiseAJour.plusRecente(parmi: releases))

        #expect(trouvee.version.description == "0.2.0")
        #expect(trouvee.dmg.lastPathComponent == "LuxVox0.2.0.dmg")
    }

    /// Une release sans `.dmg` existe — un tag posé sans avoir téléversé le
    /// fichier, par exemple. La proposer donnerait un bouton qui échoue.
    @Test("Une release sans .dmg est ignorée")
    func sansFichier() throws {
        let releases = try Self.decode("""
        [
          { "tag_name": "v0.3.0", "draft": false, "assets": [] },
          { "tag_name": "v0.2.0", "draft": false, "assets": [
              { "name": "LuxVox0.2.0.dmg",
                "browser_download_url": "https://example.invalid/a.dmg" } ] }
        ]
        """)
        #expect(MiseAJour.plusRecente(parmi: releases)?.version.description == "0.2.0")
    }

    @Test("Un brouillon est ignoré")
    func brouillon() throws {
        let releases = try Self.decode("""
        [
          { "tag_name": "v0.9.0", "draft": true, "assets": [
              { "name": "a.dmg", "browser_download_url": "https://example.invalid/a.dmg" } ] },
          { "tag_name": "v0.2.0", "draft": false, "assets": [
              { "name": "b.dmg", "browser_download_url": "https://example.invalid/b.dmg" } ] }
        ]
        """)
        #expect(MiseAJour.plusRecente(parmi: releases)?.version.description == "0.2.0")
    }

    @Test("Aucune release exploitable")
    func rien() throws {
        #expect(MiseAJour.plusRecente(parmi: try Self.decode("[]")) == nil)
    }

    /// Une étiquette illisible ne doit pas emporter les autres.
    @Test("Une étiquette illisible est sautée, pas fatale")
    func etiquetteIllisible() throws {
        let releases = try Self.decode("""
        [
          { "tag_name": "nightly", "draft": false, "assets": [
              { "name": "a.dmg", "browser_download_url": "https://example.invalid/a.dmg" } ] },
          { "tag_name": "v0.2.0", "draft": false, "assets": [
              { "name": "b.dmg", "browser_download_url": "https://example.invalid/b.dmg" } ] }
        ]
        """)
        #expect(MiseAJour.plusRecente(parmi: releases)?.version.description == "0.2.0")
    }

    // MARK: - Contre GitHub pour de vrai

    /// Éteint par défaut : une suite qui dépend du réseau est une suite qui
    /// rougit un jour sans que personne n'ait rien cassé.
    ///
    /// Il vérifie la seule chose qu'aucune fixture ne peut prouver — que
    /// GitHub accepte nos en-têtes. L'API répond **403 sans corps** à une
    /// requête sans agent, et cet échec-là ressemble à s'y méprendre à une
    /// absence de mise à jour.
    ///
    /// Pour l'allumer : **Product → Scheme → Edit Scheme → Test → Arguments
    /// → Environment Variables**, `RESEAU` = `1`.
    ///
    /// Et non pas `RESEAU=1 xcodebuild …` : l'environnement du terminal ne
    /// descend pas jusqu'à l'app-hôte des tests unitaires. Le test se
    /// contente alors d'être sauté, ce qui ressemble beaucoup à un test qui
    /// passe.
    @Test(
        "Bout en bout, contre l'API réelle",
        .enabled(if: ProcessInfo.processInfo.environment["RESEAU"] != nil)
    )
    @MainActor
    func boutEnBout() async throws {
        let amont = MiseAJour()
        amont.verifie()

        // `verifie()` pose son résultat depuis une tâche : on attend qu'il
        // quitte l'état transitoire plutôt que de dormir un temps fixe.
        let limite = Date().addingTimeInterval(30)
        while Date() < limite {
            if case .verification = amont.etat {
                try await Task.sleep(for: .milliseconds(100))
                continue
            }
            break
        }

        switch amont.etat {
        case .disponible(let version):
            #expect(version > amont.courante)
        case .aJour:
            // La version compilée est déjà la dernière publiée. C'est un
            // succès, pas un test qui n'a rien vérifié : la requête est
            // passée et la réponse s'est lue.
            break
        default:
            Issue.record("état inattendu : \(String(describing: amont.etat))")
        }
    }

    // MARK: - Le rangement du fichier

    /// Le `.dmg` d'une version déjà prise à la main la veille ne doit pas être
    /// écrasé sans un mot. Silencieusement remplacer un fichier des
    /// Téléchargements de quelqu'un est le genre de geste qu'une app n'a pas
    /// à se permettre.
    @Test("Un fichier du même nom n'est pas écrasé")
    func rangementSansEcrasement() throws {
        let fichiers = FileManager.default
        let bac = fichiers.temporaryDirectory
            .appendingPathComponent("rangement-\(UUID().uuidString)")
        try fichiers.createDirectory(at: bac, withIntermediateDirectories: true)
        defer { try? fichiers.removeItem(at: bac) }

        let arrivee = bac.appendingPathComponent("arrivée")
        try fichiers.createDirectory(at: arrivee, withIntermediateDirectories: true)

        // Trois téléchargements successifs du même nom.
        var noms: [String] = []
        for tour in 0..<3 {
            let source = bac.appendingPathComponent("temporaire-\(tour)")
            try Data("dmg".utf8).write(to: source)
            let range = try MiseAJour.range(source, sous: "LuxVox0.3.0.dmg", dans: arrivee)
            noms.append(range.lastPathComponent)
        }

        #expect(noms == ["LuxVox0.3.0.dmg", "LuxVox0.3.0 (1).dmg", "LuxVox0.3.0 (2).dmg"])
        #expect(try fichiers.contentsOfDirectory(atPath: arrivee.path).count == 3)
    }
}
