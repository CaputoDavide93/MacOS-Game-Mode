import Foundation
import GameReadyCore

/// The only place codes become words. Keys live in Localizable.xcstrings, which
/// `tools/gen_strings.py` builds from `tools/strings.py` (English + Italian) and checks
/// against every enum case.
func L(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), bundle: .main)
}

enum Copy {
    static func name(_ id: CheckID) -> String { L("check.\(id.rawValue)") }
    static func sentence(_ f: Finding) -> String { L("finding.\(f.rawValue)") }
    static func title(_ v: VerdictLevel) -> String { L("verdict.\(v.rawValue).title") }
    static func subtitle(_ v: VerdictLevel) -> String { L("verdict.\(v.rawValue).subtitle") }
    static func step(_ s: AppModel.Step) -> String { L("step.\(s.rawValue)") }
    static func event(_ k: LiveEventKind) -> String { L("event.\(k.rawValue)") }
    static func layer(_ l: Layer) -> String { L("layer.\(l.rawValue)") }
    static func item(_ i: Checklist.Item) -> String { L("checklist.\(i.rawValue).title") }
    static func help(_ i: Checklist.Item) -> String { L("checklist.\(i.rawValue).help") }
    static func grade(_ g: Grade) -> String { L("grade.\(g)") }
    static func detail(_ key: String) -> String { L("detail.\(key)") }

    /// "Wi-Fi hop: needs attention. Your Mac's Wi-Fi keeps pausing."
    static func accessibility(_ r: CheckResult) -> String {
        let finding = r.findings.first.map(sentence) ?? ""
        return "\(name(r.id)): \(grade(r.grade)). \(finding)"
    }
}
