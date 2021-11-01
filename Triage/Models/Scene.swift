//
//  Scene.swift
//  Triage
//
//  Created by Francis Li on 9/1/20.
//  Copyright © 2020 Francis Li. All rights reserved.
//

import CoreLocation
import Foundation
import RealmSwift

class Scene: BaseVersioned {
    struct Keys {
        static let name = "name"
        static let desc = "desc"
        static let urgency = "urgency"
        static let approxPatientsCount = "approxPatientsCount"
        static let approxPriorityPatientsCounts = "approxPriorityPatientsCounts"
        static let patientsCount = "patientsCount"
        static let priorityPatientsCounts = "priorityPatientsCounts"
        static let respondersCount = "respondersCount"
        static let isActive = "isActive"
        static let isMCI = "isMCI"
        static let lat = "lat"
        static let lng = "lng"
        static let address1 = "address1"
        static let address2 = "address2"
        static let cityId = "cityId"
        static let countyId = "countyId"
        static let stateId = "stateId"
        static let zip = "zip"
        static let incidentCommanderId = "incidentCommanderId"
        static let incidentCommanderAgencyId = "incidentCommanderAgencyId"
        static let closedAt = "closedAt"
    }

    @Persisted var name: String?
    @Persisted var desc: String?
    @Persisted var urgency: String?
    @Persisted var approxPatientsCount: Int?
    @Persisted var _approxPriorityPatientsCounts: String?
    var approxPriorityPatientsCounts: [Int]? {
        get {
            if let _approxPriorityPatientsCounts = _approxPriorityPatientsCounts {
                return _approxPriorityPatientsCounts.split(separator: ",").map({ Int($0) ?? 0 })
            }
            return nil
        }
        set {
            _approxPriorityPatientsCounts = newValue?.map({ String($0) }).joined(separator: ",")
        }
    }
    @Persisted var patientsCount: Int?
    @Persisted var _priorityPatientsCounts: String?
    var priorityPatientsCounts: [Int]? {
        get {
            if let _priorityPatientsCounts = _priorityPatientsCounts {
                return _priorityPatientsCounts.split(separator: ",").map({ Int($0) ?? 0 })
            }
            return nil
        }
        set {
            _priorityPatientsCounts = newValue?.map({ String($0) }).joined(separator: ",")
        }
    }
    @Persisted var respondersCount: Int?
    @Persisted var isActive: Bool = false
    @Persisted var isMCI: Bool = false
    @Persisted var lat: String?
    @Persisted var lng: String?
    var hasLatLng: Bool {
        if let lat = lat, let lng = lng, lat != "", lng != "" {
            return true
        }
        return false
    }
    var latLng: CLLocationCoordinate2D? {
        if let lat = Double(lat ?? ""), let lng = Double(lng ?? "") {
            return CLLocationCoordinate2D(latitude: CLLocationDegrees(lat), longitude: CLLocationDegrees(lng))
        }
        return nil
    }
    var latLngString: String? {
        if let lat = lat, let lng = lng {
            return "\(lat), \(lng)".trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    func clearLatLng() {
        lat = nil
        lng = nil
    }
    @Persisted var address1: String?
    @Persisted var address2: String?
    @Persisted var cityId: String?
    var city: City? {
        return realm?.object(ofType: City.self, forPrimaryKey: cityId)
    }
    @Persisted var countyId: String?
    @Persisted var stateId: String?
    var state: State? {
        return realm?.object(ofType: State.self, forPrimaryKey: stateId)
    }
    @Persisted var zip: String?
    var address: String {
        return "\(address1?.capitalized ?? "")\n\(address2?.capitalized ?? "")\n\(city?.name ?? ""), \(state?.abbr ?? "") \(zip ?? "")"
            .replacingOccurrences(of: "\n\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Persisted var closedAt: Date?
    @Persisted var incidentCommanderId: String?
    @Persisted var incidentCommanderAgencyId: String?

    override var description: String {
        return name ?? ""
    }

    override func update(from data: [String: Any]) {
        super.update(from: data)
        name = data[Keys.name] as? String
        desc = data[Keys.desc] as? String
        urgency = data[Keys.urgency] as? String
        approxPatientsCount = data[Keys.approxPatientsCount] as? Int
        approxPriorityPatientsCounts = data[Keys.approxPriorityPatientsCounts] as? [Int]
        patientsCount = data[Keys.patientsCount] as? Int
        priorityPatientsCounts = data[Keys.priorityPatientsCounts] as? [Int]
        respondersCount = data[Keys.respondersCount] as? Int
        isActive = data[Keys.isActive] as? Bool ?? false
        isMCI = data[Keys.isMCI] as? Bool ?? false
        lat = data[Keys.lat] as? String
        lng = data[Keys.lng] as? String
        address1 = data[Keys.address1] as? String
        address2 = data[Keys.address2] as? String
        cityId = data[Keys.cityId] as? String
        countyId = data[Keys.countyId] as? String
        stateId = data[Keys.stateId] as? String
        zip = data[Keys.zip] as? String
        closedAt = ISO8601DateFormatter.date(from: data[Keys.closedAt])
        incidentCommanderId = data[Keys.incidentCommanderId] as? String
        incidentCommanderAgencyId = data[Keys.incidentCommanderAgencyId] as? String
    }

    // swiftlint:disable:next cyclomatic_complexity
    override func asJSON() -> [String: Any] {
        var data = super.asJSON()
        if let value = name {
            data[Keys.name] = value
        }
        if let value = desc {
            data[Keys.desc] = value
        }
        if let value = urgency {
            data[Keys.urgency] = value
        }
        if let value = approxPatientsCount {
            data[Keys.approxPatientsCount] = value
        }
        data[Keys.approxPriorityPatientsCounts] = approxPriorityPatientsCounts
        data[Keys.isMCI] = isMCI
        if let value = lat {
            data[Keys.lat] = value
        }
        if let value = lng {
            data[Keys.lng] = value
        }
        if let value = address1 {
            data[Keys.address1] = value
        }
        if let value = address2 {
            data[Keys.address2] = value
        }
        if let value = cityId {
            data[Keys.cityId] = value
        }
        if let value = countyId {
            data[Keys.countyId] = value
        }
        if let value = stateId {
            data[Keys.stateId] = value
        }
        if let value = zip {
            data[Keys.zip] = value
        }
        return data
    }
}
