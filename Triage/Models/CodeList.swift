//
//  List.swift
//  Triage
//
//  Created by Francis Li on 12/7/21.
//  Copyright © 2021 Francis Li. All rights reserved.
//

import RealmSwift

class CodeList: Base {
    struct Keys {
        static let fields = "fields"
    }
    @Persisted var fields: List<String>
    @Persisted(originProperty: "list") var sections: LinkingObjects<CodeListSection>
    @Persisted(originProperty: "list") var items: LinkingObjects<CodeListItem>

    override func update(from data: [String: Any]) {
        super.update(from: data)
        fields.removeAll()
        if let fields = data[Keys.fields] as? [String] {
            self.fields.append(objectsIn: fields)
        }
    }

    override func asJSON() -> [String: Any] {
        var json = super.asJSON()
        json[Keys.fields] = fields.map { $0 }
        return json
    }
}

class CodeListSection: Base {
    struct Keys {
        static let listId = "listId"
        static let name = "name"
        static let position = "position"
    }
    @Persisted var list: CodeList?
    @Persisted var name: String?
    @Persisted var position: Int?
    @Persisted(originProperty: "section") var items: LinkingObjects<CodeListItem>

    override func update(from data: [String: Any]) {
        super.update(from: data)
        list = (realm ?? AppRealm.open()).object(ofType: CodeList.self, forPrimaryKey: data[Keys.listId])
        name = data[Keys.name] as? String
        position = data[Keys.position] as? Int
    }

    override func asJSON() -> [String: Any] {
        var json = super.asJSON()
        if let value = name {
            json[Keys.name] = value
        }
        if let value = position {
            json[Keys.position] = value
        }
        return json
    }
}

class CodeListItem: Base {
    struct Keys {
        static let listId = "listId"
        static let sectionId = "sectionId"
        static let system = "system"
        static let code = "code"
        static let name = "name"
    }
    @Persisted var list: CodeList?
    @Persisted var section: CodeListSection?
    @Persisted var system: String?
    @Persisted var code: String?
    @Persisted var name: String?

    override func update(from data: [String: Any]) {
        super.update(from: data)
        list = (realm ?? AppRealm.open()).object(ofType: CodeList.self, forPrimaryKey: data[Keys.listId])
        section = (realm ?? AppRealm.open()).object(ofType: CodeListSection.self, forPrimaryKey: data[Keys.sectionId])
        system = data[Keys.system] as? String
        code = data[Keys.code] as? String
        name = data[Keys.name] as? String
    }

    override func asJSON() -> [String: Any] {
        var json = super.asJSON()
        if let value = system {
            json[Keys.system] = value
        }
        if let value = code {
            json[Keys.code] = value
        }
        if let value = name {
            json[Keys.name] = value
        }
        return json
    }
}