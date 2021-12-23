//
//  Narrative.swift
//  Triage
//
//  Created by Francis Li on 11/9/21.
//  Copyright © 2021 Francis Li. All rights reserved.
//

import RealmSwift

class Narrative: BaseVersioned, NemsisBacked {
    struct Keys {
        static let data = "data"
    }
    @Persisted var _data: Data?

    @objc var text: String? {
        get {
            return getFirstNemsisValue(forJSONPath: "/eNarrative/eNarrative.01")?.text
        }
        set {
            setNemsisValue(NemsisValue(text: newValue), forJSONPath: "/eNarrative/eNarrative.01")
        }
    }

    override func asJSON() -> [String: Any] {
        var json = super.asJSON()
        json[Keys.data] = data
        return json
    }
}
