//
//  CharacterEvidenceExtractor.swift
//  SwiftVoxAlta
//
//  Extracts character evidence from screenplay elements for voice design analysis.
//

import Foundation
import SwiftCompartido

/// Extracts `CharacterEvidence` from a sequence of screenplay elements.
///
/// Walks the element array sequentially. When a `.character` element is found,
/// collects subsequent `.dialogue` and `.parenthetical` elements until the next
/// `.character` or non-dialogue element. Also tracks which scene headings and
/// action lines mention each character by name (case-insensitive).
public struct CharacterEvidenceExtractor: Sendable {

    /// Extract character evidence from an array of screenplay elements.
    ///
    /// - Parameter elements: Screenplay elements in document order. Accepts any type
    ///   conforming to `GuionElementProtocol` (e.g., `GuionElement`, `GuionElementModel`).
    /// - Returns: A dictionary keyed by character name (normalized to uppercase)
    ///   mapping to the collected `CharacterEvidence`.
    public static func extract(from elements: [any GuionElementProtocol]) -> [String: CharacterEvidence] {
        var evidenceByName: [String: CharacterEvidence] = [:]

        // Track the most recent scene heading for associating with characters
        var currentSceneHeading: String?

        // Track which characters have been associated with the current scene heading
        var charactersInCurrentScene: Set<String> = []

        // First pass: extract dialogue blocks and track scene headings
        var currentCharacterName: String?

        for element in elements {
            switch element.elementType {
            case .sceneHeading:
                currentSceneHeading = element.elementText
                charactersInCurrentScene = []
                currentCharacterName = nil

            case .character:
                let name = normalizeCharacterName(element.elementText)
                currentCharacterName = name

                // Initialize evidence if this is a new character
                if evidenceByName[name] == nil {
                    evidenceByName[name] = CharacterEvidence(characterName: name)
                }

                // Associate this character with the current scene heading
                if let heading = currentSceneHeading, !charactersInCurrentScene.contains(name) {
                    evidenceByName[name]?.sceneHeadings.append(heading)
                    charactersInCurrentScene.insert(name)
                }

            case .dialogue:
                if let name = currentCharacterName {
                    evidenceByName[name]?.dialogueLines.append(element.elementText)
                }

            case .parenthetical:
                if let name = currentCharacterName {
                    evidenceByName[name]?.parentheticals.append(element.elementText)
                }

            default:
                // Any non-dialogue element ends the current dialogue block
                if element.elementType != .dialogue && element.elementType != .parenthetical {
                    currentCharacterName = nil
                }
            }
        }

        // Second pass: scan action lines for character name mentions
        let characterNames = Array(evidenceByName.keys)
        for element in elements {
            if element.elementType == .action {
                let actionText = element.elementText.uppercased()
                for name in characterNames {
                    if actionText.contains(name) {
                        evidenceByName[name]?.actionMentions.append(element.elementText)
                    }
                }
            }
        }

        return evidenceByName
    }

    /// Normalize a character name by trimming whitespace and converting to uppercase.
    ///
    /// Also strips common Fountain extensions like "(V.O.)", "(O.S.)", "(O.C.)",
    /// "(CONT'D)", etc.
    private static func normalizeCharacterName(_ rawName: String) -> String {
        var name = rawName.trimmingCharacters(in: .whitespaces)

        // Remove common Fountain character extensions in parentheses
        // e.g., "JOHN (V.O.)" -> "JOHN", "MARY (CONT'D)" -> "MARY"
        let extensionPattern = #"\s*\((?:V\.O\.|O\.S\.|O\.C\.|CONT'D|CONT\.)\)\s*$"#
        if let regex = try? NSRegularExpression(pattern: extensionPattern, options: .caseInsensitive) {
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            name = regex.stringByReplacingMatches(in: name, range: range, withTemplate: "")
        }

        return name.uppercased().trimmingCharacters(in: .whitespaces)
    }
}
