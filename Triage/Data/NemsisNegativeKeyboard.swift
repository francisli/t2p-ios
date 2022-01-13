//
//  NemsisNegativeKeyboard.swift
//  Triage
//
//  Created by Francis Li on 12/13/21.
//  Copyright © 2021 Francis Li. All rights reserved.
//

import Foundation
import PRKit

class NemsisNegativeKeyboard: SelectKeyboard, KeyboardSource {
    var negatives: [NemsisNegative]

    init(negatives: [NemsisNegative]) {
        self.negatives = negatives
        super.init()
        source = self
    }

    required init?(coder: NSCoder) {
        self.negatives = []
        super.init(coder: coder)
        source = self
    }

    // MARK: - KeyboardSource

    var name: String {
        return "NemsisNegativeKeyboard.title".localized
    }

    func count() -> Int {
        return negatives.count
    }

    func firstIndex(of value: NSObject) -> Int? {
        guard let value = value as? String else { return nil }
        return negatives.firstIndex(where: { $0.rawValue == value })
    }

    func search(_ query: String?) {

    }

    func title(for value: NSObject?) -> String? {
        guard let value = value as? String else { return nil }
        return negatives.first(where: {$0.rawValue == value})?.description
    }

    func title(at index: Int) -> String? {
        return negatives[index].description
    }

    func value(at index: Int) -> NSObject? {
        return negatives[index].rawValue as NSObject
    }
}
