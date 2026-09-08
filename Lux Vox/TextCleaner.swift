//
//  TextCleaner.swift
//  Lux Vox
//

import Foundation

/// Passe 1 du nettoyage (cahier des charges, §4) : traitement de texte pur,
/// sans modèle de langue, coût négligeable.
///
/// Aucune dépendance à SwiftUI, à l'audio ni au `MainActor` : la fonction est
/// pure, donc testable sans lancer l'app.
///
/// Principe directeur appliqué à la lettre : **on retire, on ne réécrit pas.**
/// Aucun mot n'est remplacé par un synonyme et aucune ponctuation qui n'a pas
/// été dictée n'est ajoutée en fin d'énoncé — une dictée sert aussi à remplir
/// un champ de recherche ou une ligne de terminal, où un point final inventé
/// est une erreur.
///
/// `nonisolated` explicite : la cible app compile en
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, ce qui isolerait ce type sur
/// l'UI par défaut. Le nettoyage doit au contraire pouvoir s'exécuter hors du
/// `MainActor` — c'est ce qui permet de tenir le budget de 2 s — et être
/// appelé depuis une suite de tests headless.
nonisolated enum TextCleaner {

    /// Nettoie une transcription brute : ponctuation dictée, tics de langage,
    /// bégaiements, majuscules et espaces typographiques françaises.
    static func clean(_ raw: String) -> String {
        var tokens = decoupe(raw)
        tokens = appliquePonctuationDictee(tokens)
        tokens = retireBegaiements(tokens)
        tokens = retireTics(tokens)
        return assemble(tokens)
    }

    // MARK: - Modèle

    /// Un mot, un signe de ponctuation, ou un retour à la ligne. Travailler sur
    /// des unités plutôt que sur des expressions régulières enchaînées rend
    /// chaque règle indépendante et prévisible.
    private enum Token: Equatable {
        case mot(String)
        case ponctuation(String)
        case saut
    }

    private static let signes: Set<Character> = [",", ".", "?", "!", ":", ";"]

    // MARK: - Découpe

    private static func decoupe(_ texte: String) -> [Token] {
        var tokens: [Token] = []
        let lignes = texte.split(separator: "\n", omittingEmptySubsequences: false)

        for (index, ligne) in lignes.enumerated() {
            if index > 0 { tokens.append(.saut) }
            for morceau in ligne.split(whereSeparator: { $0.isWhitespace }) {
                ajoute(morceau, a: &tokens)
            }
        }
        return tokens
    }

    private static func ajoute(_ morceau: Substring, a tokens: inout [Token]) {
        var coeur = morceau
        var suffixes: [Token] = []

        while let dernier = coeur.last, signes.contains(dernier) {
            suffixes.insert(.ponctuation(String(dernier)), at: 0)
            coeur = coeur.dropLast()
        }
        // Ponctuation orpheline en tête : artefact de transcription, on la jette.
        while let premier = coeur.first, signes.contains(premier) {
            coeur = coeur.dropFirst()
        }

        if !coeur.isEmpty { tokens.append(.mot(String(coeur))) }
        tokens.append(contentsOf: suffixes)
    }

    // MARK: - Ponctuation dictée

    /// Les séquences les plus longues d'abord : « point d'interrogation » doit
    /// être reconnu avant « point ».
    private static let ponctuationDictee: [(sequence: [String], token: Token)] = [
        (["retour", "a", "la", "ligne"], .saut),
        (["point", "d'interrogation"], .ponctuation("?")),
        (["point", "d'exclamation"], .ponctuation("!")),
        (["point", "virgule"], .ponctuation(";")),
        (["point-virgule"], .ponctuation(";")),
        (["deux", "points"], .ponctuation(":")),
        (["a", "la", "ligne"], .saut),
        (["nouvelle", "ligne"], .saut),
        (["virgule"], .ponctuation(",")),
        (["point"], .ponctuation(".")),
    ]

    /// Devant un déterminant, « point » est un nom commun (« un point
    /// important »), pas une ponctuation dictée.
    private static let determinantsAvantPoint: Set<String> = [
        "un", "le", "ce", "cet", "du", "au", "a", "mon", "ton", "son",
        "notre", "votre", "leur", "quel", "chaque", "meme", "tel", "premier",
        "dernier", "seul", "autre",
    ]

    private static func appliquePonctuationDictee(_ tokens: [Token]) -> [Token] {
        var sortie: [Token] = []
        var index = 0

        boucle: while index < tokens.count {
            guard case .mot = tokens[index] else {
                sortie.append(tokens[index])
                index += 1
                continue
            }

            for regle in ponctuationDictee where correspond(regle.sequence, dans: tokens, a: index) {
                if regle.sequence == ["point"], estNomCommun(avant: sortie) {
                    break
                }
                sortie.append(regle.token)
                index += regle.sequence.count
                continue boucle
            }

            sortie.append(tokens[index])
            index += 1
        }
        return sortie
    }

    private static func correspond(_ sequence: [String], dans tokens: [Token], a index: Int) -> Bool {
        guard index + sequence.count <= tokens.count else { return false }
        for (decalage, attendu) in sequence.enumerated() {
            guard case .mot(let mot) = tokens[index + decalage],
                  normalise(mot) == attendu else { return false }
        }
        return true
    }

    private static func estNomCommun(avant sortie: [Token]) -> Bool {
        guard case .mot(let precedent)? = sortie.last else { return false }
        return determinantsAvantPoint.contains(normalise(precedent))
    }

    // MARK: - Bégaiements

    /// Mots dont la répétition immédiate est presque toujours voulue : elle
    /// porte une intensité (« très très bien »), pas une hésitation.
    private static let repetitionsLegitimes: Set<String> = [
        "tres", "trop", "bien", "non", "oui", "vite", "beaucoup", "presque",
        "doucement", "loin", "pres", "tout", "peu",
    ]

    /// Trois occurrences ou plus d'un même mot sont toujours un bégaiement.
    /// Deux seulement le sont, sauf pour les intensificateurs ci-dessus.
    private static func retireBegaiements(_ tokens: [Token]) -> [Token] {
        var sortie: [Token] = []
        var index = 0

        while index < tokens.count {
            guard case .mot(let mot) = tokens[index] else {
                sortie.append(tokens[index])
                index += 1
                continue
            }

            var fin = index + 1
            while fin < tokens.count,
                  case .mot(let suivant) = tokens[fin],
                  normalise(suivant) == normalise(mot) {
                fin += 1
            }

            let occurrences = fin - index
            let conserve = occurrences == 2 && repetitionsLegitimes.contains(normalise(mot))
            sortie.append(contentsOf: conserve ? Array(tokens[index..<fin]) : [tokens[index]])
            index = fin
        }
        return sortie
    }

    // MARK: - Tics de langage

    /// Hésitations pures : jamais porteuses de sens, retirées partout.
    private static let ticsInconditionnels: Set<String> = [
        "euh", "heu", "heum", "hum", "hmm", "mmh", "bah", "ben", "bein",
    ]

    /// Locutions de remplissage, retirées partout (§4 du cahier des charges).
    private static let ticsComposes: [[String]] = [
        ["du", "coup"],
        ["en", "fait"],
    ]

    /// Ne sont des tics qu'en fin d'énoncé : « voilà le résultat » garde son
    /// sens, « c'est bon voilà » non.
    private static let ticsTerminaux: Set<String> = ["quoi", "voila"]

    /// Contextes où « quoi » est interrogatif et doit rester : « tu fais quoi »,
    /// « à quoi bon ».
    private static let motsAvantQuoiInterrogatif: Set<String> = [
        "de", "a", "en", "par", "pour", "sur", "dans", "avec", "sans",
        "fais", "fait", "faites", "dis", "dit", "dites", "veux", "veut",
        "voulez", "sais", "sait", "savez", "pense", "penses", "pensez",
        "cherche", "cherches", "cherchez", "attends", "attend", "attendez",
        "raconte", "racontes", "racontez", "c'est", "cest",
    ]

    private static func retireTics(_ tokens: [Token]) -> [Token] {
        var sortie: [Token] = []
        var index = 0

        boucle: while index < tokens.count {
            guard case .mot(let mot) = tokens[index] else {
                sortie.append(tokens[index])
                index += 1
                continue
            }

            if ticsInconditionnels.contains(normalise(mot)) {
                index += 1
                continue
            }

            for locution in ticsComposes where correspond(locution, dans: tokens, a: index) {
                index += locution.count
                continue boucle
            }

            sortie.append(tokens[index])
            index += 1
        }

        return retireTicsTerminaux(sortie)
    }

    /// Un tic terminal peut en démasquer un autre — « c'est bon quoi voilà »
    /// perd « voilà », ce qui met « quoi » en position terminale à son tour. On
    /// itère donc jusqu'au point fixe.
    private static func retireTicsTerminaux(_ tokens: [Token]) -> [Token] {
        var sortie = tokens
        var encore = true

        while encore {
            encore = false
            for index in sortie.indices {
                guard case .mot(let mot) = sortie[index],
                      ticsTerminaux.contains(normalise(mot)),
                      estEnFinDeSegment(sortie, index),
                      !estSeulMotDuSegment(sortie, index) else { continue }

                if normalise(mot) == "quoi", estInterrogatif(sortie, index) { continue }

                sortie.remove(at: index)
                encore = true
                break
            }
        }
        return sortie
    }

    private static func estEnFinDeSegment(_ tokens: [Token], _ index: Int) -> Bool {
        let suivant = index + 1
        guard suivant < tokens.count else { return true }
        switch tokens[suivant] {
        case .mot: return false
        case .ponctuation, .saut: return true
        }
    }

    /// « Voilà. » dicté seul est une phrase complète : on ne la vide pas.
    private static func estSeulMotDuSegment(_ tokens: [Token], _ index: Int) -> Bool {
        guard index > 0 else { return true }
        switch tokens[index - 1] {
        case .mot: return false
        case .ponctuation, .saut: return true
        }
    }

    private static func estInterrogatif(_ tokens: [Token], _ index: Int) -> Bool {
        if index + 1 < tokens.count, tokens[index + 1] == .ponctuation("?") { return true }
        guard index > 0, case .mot(let precedent) = tokens[index - 1] else { return false }
        return motsAvantQuoiInterrogatif.contains(normalise(precedent))
    }

    // MARK: - Assemblage

    /// Espace fine insécable avant `? ! ;` et insécable avant `:`, conformément
    /// à l'usage typographique français.
    private static let fineInsecable = "\u{202F}"
    private static let insecable = "\u{00A0}"

    private static func assemble(_ tokens: [Token]) -> String {
        var sortie = ""
        var debutDePhrase = true

        for token in tokens {
            switch token {
            case .saut:
                sortie += "\n"
                debutDePhrase = true

            case .ponctuation(let signe):
                switch signe {
                case ",", ".":
                    sortie += signe
                case ":":
                    sortie += insecable + signe
                default:
                    sortie += fineInsecable + signe
                }
                debutDePhrase = (signe == "." || signe == "?" || signe == "!")

            case .mot(let mot):
                if !sortie.isEmpty && !sortie.hasSuffix("\n") { sortie += " " }
                sortie += debutDePhrase ? capitalise(mot) : mot
                debutDePhrase = false
            }
        }
        return sortie.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitalise(_ mot: String) -> String {
        guard let premiere = mot.first else { return mot }
        return premiere.uppercased() + mot.dropFirst()
    }

    // MARK: - Normalisation

    /// Minuscules, apostrophes typographiques ramenées à `'`, accents retirés :
    /// les règles se comparent sur une forme stable, le texte rendu garde la
    /// sienne.
    private static func normalise(_ mot: String) -> String {
        mot.replacingOccurrences(of: "\u{2019}", with: "'")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}
