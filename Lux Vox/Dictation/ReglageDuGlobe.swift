//
//  ReglageDuGlobe.swift
//  Lux Vox
//

import Foundation

/// Ce que macOS attache à la touche 🌐 — et comment le lui reprendre.
///
/// ## Pourquoi ce réglage est incontournable
///
/// Le tap clavier voit passer 🌐 mais ne la consomme pas, et ne le peut pas :
/// c'est un **modificateur**, et avaler son `flagsChanged` casserait Fn+F1…F12
/// et tout le reste (voir la note en fin de `KeyboardTrigger`). L'action que
/// macOS attache à la touche ne se neutralise donc pas par le code — seulement
/// par ce réglage.
///
/// ## Une seule clé, et non deux
///
/// Le double-appui qui lance la dictée d'Apple n'est pas un réglage séparé :
/// c'est la valeur `dicteeDApple` de celui-ci — vérifié à l'écran, le panneau
/// Clavier affiche alors « Appuyer sur 🌐 pour : Lancer la dictée (appuyer
/// deux fois sur 🌐) ». Il n'y a donc qu'une valeur à lire, et une à écrire.
///
/// ## Écrire chez quelqu'un d'autre
///
/// Le domaine appartient à HIToolbox. L'app n'étant pas sandboxée (cahier §6),
/// `CFPreferences` l'accepte : c'est mot pour mot ce que fait un
/// `defaults write com.apple.HIToolbox AppleFnUsageType`, et c'est aussi
/// réversible — le panneau Clavier reprend la main à tout moment.
nonisolated enum ReglageDuGlobe: Int, CaseIterable, Sendable {
    /// La seule valeur qui laisse la touche à Lux Vox.
    case rienFaire = 0
    case sourceDeSaisie = 1
    case emoji = 2
    case dicteeDApple = 3

    /// Tel que le panneau Clavier le nomme, pour que la bulle dise à
    /// l'utilisateur ce qu'il abandonne exactement.
    var libelle: String {
        switch self {
        case .rienFaire: "Ne rien faire"
        case .sourceDeSaisie: "Changer de source de saisie"
        case .emoji: "Afficher les emoji et symboles"
        case .dicteeDApple: "Lancer la dictée d'Apple"
        }
    }

    /// Calculées et non rangées : une `CFString` n'est pas `Sendable`, et le
    /// mode Swift 6 refuse de la laisser vivre en propriété statique.
    private static var domaine: CFString { "com.apple.HIToolbox" as CFString }
    private static var clef: CFString { "AppleFnUsageType" as CFString }

    /// Ce que la touche fait en ce moment.
    ///
    /// `nil` quand la clé est absente : macOS applique alors sa valeur par
    /// défaut, qui dépend du modèle de clavier. On ne la devine pas — la
    /// seule chose qui compte est qu'elle ne vaut pas `rienFaire`, sans quoi
    /// la clé aurait été écrite.
    static var actuel: ReglageDuGlobe? {
        CFPreferencesAppSynchronize(domaine)
        guard let brut = CFPreferencesCopyAppValue(clef, domaine) as? Int else { return nil }
        return ReglageDuGlobe(rawValue: brut)
    }

    /// Vrai quand la touche est libre — donc utilisable comme déclencheur.
    static var estLibre: Bool { actuel == .rienFaire }

    /// Reprend la touche à macOS. Renvoie `false` si l'écriture n'a pas pris,
    /// auquel cas il reste le panneau Clavier.
    ///
    /// La relecture n'est pas de la coquetterie : `CFPreferencesAppSynchronize`
    /// peut répondre `true` sans que la valeur soit visible ensuite, et une
    /// étape cochée à tort coûterait plus cher qu'un bouton qui échoue
    /// franchement.
    @discardableResult
    static func libere() -> Bool {
        CFPreferencesSetAppValue(clef, NSNumber(value: rienFaire.rawValue), domaine)
        guard CFPreferencesAppSynchronize(domaine) else { return false }
        return estLibre
    }
}
