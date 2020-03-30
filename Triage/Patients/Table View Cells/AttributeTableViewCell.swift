//
//  AttributeTableViewCell.swift
//  Triage
//
//  Created by Francis Li on 11/2/19.
//  Copyright © 2019 Francis Li. All rights reserved.
//

import UIKit

@objc protocol AttributeTableViewCellDelegate {
    @objc optional func attributeTableViewCell(_ cell: AttributeTableViewCell, didChange text: String)
    @objc optional func attributeTableViewCellDidReturn(_ cell: AttributeTableViewCell)
}

enum AttributeTableViewCellType {
    case string
    case number
}

class AttributeTableViewCell: PatientTableViewCell, PatientTableViewCellBackground, UITextFieldDelegate {
    @IBOutlet weak var customBackgroundView: UIView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var valueField: UITextField!

    var attribute: String!
    var attributeType: AttributeTableViewCellType = .string
    weak var delegate: AttributeTableViewCellDelegate?

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
    override func configure(from patient: Patient) {
        titleLabel.text = NSLocalizedString("Patient.\(attribute ?? "")", comment: "")
        if let value = patient.value(forKey: attribute) {
            valueField.text = String(describing: value)
        } else {
            valueField.text = nil
        }
        switch attributeType {
        case .string:
            valueField.keyboardType = .default
        case .number:
            valueField.keyboardType = .numberPad
        }
        valueField.returnKeyType = .next
    }

    override func becomeFirstResponder() -> Bool {
        return valueField.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        return valueField.resignFirstResponder()
    }

    // MARK: - UITableViewCell

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        valueField.isUserInteractionEnabled = editing
        valueField.clearButtonMode = editing ? .always : .never
    }
    
    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        delegate?.attributeTableViewCellDidReturn?(self)
        return true
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let text = ((textField.text ?? "") as NSString).replacingCharacters(in: range, with: string)
        DispatchQueue.main.async { [weak self] in
            if let self = self {
                self.delegate?.attributeTableViewCell?(self, didChange: text)
            }
        }
        return true
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        DispatchQueue.main.async { [weak self] in
            if let self = self {
                self.delegate?.attributeTableViewCell?(self, didChange: "")
            }
        }
        return true
    }
}
