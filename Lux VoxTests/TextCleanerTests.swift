//
//  TextCleanerTests.swift
//  Lux VoxTests
//

import Testing
@testable import Lux_Vox

/// Table texte-entrée / texte-attendu de la passe 1 (cahier des charges, §4).
///
/// Elle tourne sans lancer l'app, sans micro et sans permission : c'est ce qui
/// rend le réglage des règles supportable dans la durée.
@Suite("Nettoyage — passe 1")
struct TextCleanerTests {

    /// Espaces typographiques françaises, écrites explicitement pour que les
    /// attentes du test ne dépendent pas de l'apparence du fichier source.
    static let fine = "\u{202F}"
    static let insecable = "\u{00A0}"

    // MARK: - Les exemples du cahier des charges

    @Test(
        "Exemples de la section 4",
        arguments: [
            ("euh je voulais heu te dire", "Je voulais te dire"),
            ("je je je pense que", "Je pense que"),
            ("c'est bon quoi voilà", "C'est bon"),
            ("du coup en fait bah oui", "Oui"),
        ]
    )
    func exemplesDuCahier(entree: String, attendu: String) {
        #expect(TextCleaner.clean(entree) == attendu)
    }

    // MARK: - Hésitations

    @Test(
        "Les tics de remplissage disparaissent",
        arguments: [
            ("euh bonjour", "Bonjour"),
            ("heu alors voilà le plan", "Alors voilà le plan"),
            ("hum je crois", "Je crois"),
            ("ben je sais pas", "Je sais pas"),
            ("du coup je pars", "Je pars"),
            ("en fait c'est simple", "C'est simple"),
        ]
    )
    func ticsRetires(entree: String, attendu: String) {
        #expect(TextCleaner.clean(entree) == attendu)
    }

    // MARK: - Bégaiements

    @Test(
        "Les répétitions immédiates sont réduites",
        arguments: [
            ("je je pense", "Je pense"),
            ("le le le fichier", "Le fichier"),
            ("c'est c'est c'est important", "C'est important"),
        ]
    )
    func begaiementsRetires(entree: String, attendu: String) {
        #expect(TextCleaner.clean(entree) == attendu)
    }

    @Test("Une répétition d'intensité est voulue, on la garde")
    func repetitionLegitime() {
        #expect(TextCleaner.clean("très très bien") == "Très très bien")
        #expect(TextCleaner.clean("non non") == "Non non")
    }

    @Test("Trois occurrences restent un bégaiement, même pour un intensificateur")
    func repetitionTripleTouteFois() {
        #expect(TextCleaner.clean("non non non") == "Non")
    }

    // MARK: - Ponctuation dictée

    @Test("Virgule et point")
    func ponctuationSimple() {
        #expect(TextCleaner.clean("bonjour virgule comment vas-tu") == "Bonjour, comment vas-tu")
        #expect(TextCleaner.clean("bonjour point comment vas-tu") == "Bonjour. Comment vas-tu")
    }

    @Test("Point d'interrogation et point d'exclamation")
    func ponctuationComposee() {
        #expect(TextCleaner.clean("ça va point d'interrogation") == "Ça va\(Self.fine)?")
        #expect(TextCleaner.clean("génial point d'exclamation") == "Génial\(Self.fine)!")
    }

    @Test("Deux-points et point-virgule")
    func ponctuationDeuxPoints() {
        #expect(TextCleaner.clean("attention deux points c'est important")
                == "Attention\(Self.insecable): c'est important")
        #expect(TextCleaner.clean("premier point virgule second")
                == "Premier\(Self.fine); second")
    }

    @Test("À la ligne produit un vrai retour à la ligne")
    func retourALaLigne() {
        #expect(TextCleaner.clean("première ligne à la ligne deuxième ligne")
                == "Première ligne\nDeuxième ligne")
    }

    // MARK: - Ce qui porte du sens reste intact

    @Test(
        "Les mots qui portent du sens ne sont pas retirés",
        arguments: [
            // « point » est ici un nom commun, pas une ponctuation dictée.
            ("un point important", "Un point important"),
            ("le point de départ", "Le point de départ"),
            // « voilà » n'est un tic qu'en fin d'énoncé.
            ("voilà le résultat", "Voilà le résultat"),
            // « quoi » interrogatif.
            ("tu fais quoi", "Tu fais quoi"),
            ("à quoi", "À quoi"),
            // Seul mot de l'énoncé : c'est une phrase complète.
            ("voilà", "Voilà"),
        ]
    )
    func sensPreserve(entree: String, attendu: String) {
        #expect(TextCleaner.clean(entree) == attendu)
    }

    // MARK: - Mise en forme

    @Test("Majuscule en début de phrase, pas ailleurs")
    func capitalisation() {
        #expect(TextCleaner.clean("bonjour point à bientôt") == "Bonjour. À bientôt")
        #expect(TextCleaner.clean("bonjour virgule à bientôt") == "Bonjour, à bientôt")
    }

    @Test("Les espaces surnuméraires sont absorbées")
    func espacesNormalisees() {
        #expect(TextCleaner.clean("  je    pense   ") == "Je pense")
    }

    // MARK: - Robustesse

    @Test(
        "Entrées dégénérées",
        arguments: [
            ("", ""),
            ("   ", ""),
            ("\n\n", ""),
            // Une dictée qui n'était qu'une hésitation ne produit rien : mieux
            // vaut n'injecter aucun texte que du bruit.
            ("euh", ""),
            ("euh euh heu", ""),
        ]
    )
    func entreesDegenerees(entree: String, attendu: String) {
        #expect(TextCleaner.clean(entree) == attendu)
    }

    // MARK: - Propriétés

    /// Le texte injecté peut être renvoyé dans la passe 1 (reprise, passe 2
    /// abandonnée sur délai) : un second nettoyage ne doit rien abîmer.
    @Test(
        "Nettoyer deux fois donne le même résultat",
        arguments: [
            "euh je voulais heu te dire",
            "bonjour virgule comment vas-tu",
            "ça va point d'interrogation",
            "première ligne à la ligne deuxième ligne",
            "attention deux points c'est important",
        ]
    )
    func idempotence(entree: String) {
        let unePasse = TextCleaner.clean(entree)
        #expect(TextCleaner.clean(unePasse) == unePasse)
    }

    /// Décision de conception, à confirmer à l'usage : la passe 1 n'invente
    /// aucune ponctuation finale. Le tableau du §4 montre « C'est bon. » et
    /// « Oui. » avec un point que l'utilisateur n'a pas dicté, alors que
    /// « Je voulais te dire » n'en a pas — les trois exemples ne suivent pas la
    /// même règle. Une dictée sert aussi à remplir un champ de recherche ou une
    /// ligne de terminal, où un point inventé est une erreur ; conformément au
    /// principe directeur, on ne rajoute rien.
    @Test("Aucune ponctuation finale n'est inventée")
    func aucunePonctuationInventee() {
        #expect(TextCleaner.clean("c'est bon quoi voilà") == "C'est bon")
        #expect(TextCleaner.clean("du coup en fait bah oui") == "Oui")
    }

    /// Une transcription ne doit jamais perdre de vocabulaire au-delà des tics
    /// listés : la passe 1 retire, elle ne remplace pas.
    @Test("Aucun mot substantiel n'est remplacé")
    func aucunRemplacement() {
        let entree = "euh le fichier de configuration est corrompu"
        let sortie = TextCleaner.clean(entree)
        for mot in ["fichier", "configuration", "corrompu"] {
            #expect(sortie.contains(mot))
        }
    }

    // MARK: - Guillemets et parenthèses

    @Test("Les guillemets dictés encadrent le texte")
    func guillemets() {
        #expect(TextCleaner.clean("il a dit ouvrez les guillemets je viens fermez les guillemets")
                == "Il a dit «\(Self.insecable)je viens\(Self.insecable)»")
    }

    /// « guillemets » dit seul est ambigu : c'est l'alternance qui tranche.
    @Test("Guillemets seuls : le premier ouvre, le second ferme")
    func guillemetsAlternance() {
        #expect(TextCleaner.clean("il a dit guillemets je viens guillemets")
                == "Il a dit «\(Self.insecable)je viens\(Self.insecable)»")
    }

    /// Un guillemet orphelin est plus gênant qu'un guillemet ajouté.
    @Test("Une citation restée ouverte est refermée")
    func citationRefermee() {
        #expect(TextCleaner.clean("il a dit guillemets je viens")
                == "Il a dit «\(Self.insecable)je viens\(Self.insecable)»")
    }

    @Test("Les parenthèses collent au texte, sans espace intérieur")
    func parentheses() {
        #expect(TextCleaner.clean("le client ouvrez la parenthèse le grand fermez la parenthèse arrive")
                == "Le client (le grand) arrive")
    }

    // MARK: - Listes

    @Test("« tiret » en tête de ligne ouvre une puce")
    func listeAPuces() {
        #expect(TextCleaner.clean("tiret du pain à la ligne tiret du lait")
                == "- Du pain\n- Du lait")
    }

    @Test("Les ordinaux dictés produisent une liste numérotée")
    func listeNumerotee() {
        #expect(TextCleaner.clean("premièrement relire à la ligne deuxièmement corriger")
                == "1. Relire\n2. Corriger")
    }

    /// Sans marqueur en tête de ligne, rien n'est transformé : « il est arrivé
    /// premier » n'est pas une liste, et un tiret au milieu d'une phrase non plus.
    @Test("Un marqueur hors tête de ligne ne crée pas de liste")
    func pasDeListeAuMilieu() {
        #expect(TextCleaner.clean("le trait d'union est un tiret") == "Le trait d'union est un tiret")
    }

    @Test("Une liste ferme la phrase précédente sans ligne vide")
    func listeApresPhrase() {
        #expect(TextCleaner.clean("à faire deux points à la ligne tiret relire")
                == "À faire\(Self.insecable):\n- Relire")
    }
}
