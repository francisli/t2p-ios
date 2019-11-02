//
//  PatientTableViewController.swift
//  Triage
//
//  Created by Francis Li on 11/1/19.
//  Copyright © 2019 Francis Li. All rights reserved.
//

import RealmSwift
import UIKit

let INFO = ["firstName", "lastName", "age"]
let INFO_TYPES: [AttributeTableViewCellType] = [.string, .string, .number]

let VITALS = ["respiratoryRate", "pulse", "capillaryRefill", "bloodPressure"]
let VITALS_TYPES: [AttributeTableViewCellType] = [.number, .number, .number, .string]


class PatientTableViewController: UITableViewController, AttributeTableViewCellDelegate, LatLngTableViewCellDelegate, ObservationTableViewControllerDelegate, PriorityViewDelegate {
    enum Section: Int {
        case portrait = 0
        case priority
        case location
        case info
        case vitals
        case observations
    }
    
    var patient: Patient!
    var notificationToken: NotificationToken?
    
    deinit {
        notificationToken?.invalidate()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UINib(nibName: "AttributeTableViewCell", bundle: nil), forCellReuseIdentifier: "Attribute")
        tableView.register(UINib(nibName: "LatLngTableViewCell", bundle: nil), forCellReuseIdentifier: "LatLng")
        tableView.register(UINib(nibName: "PortraitTableViewCell", bundle: nil), forCellReuseIdentifier: "Portrait")
        tableView.register(UINib(nibName: "PriorityTableViewCell", bundle: nil), forCellReuseIdentifier: "Priority")
        tableView.tableFooterView = UIView()

        title = "\(patient.firstName ?? "") \(patient.lastName ?? "")".trimmingCharacters(in: .whitespacesAndNewlines)
        
        if patient.id != nil {
            notificationToken = patient.observe { [weak self] (change) in
                self?.didObserveChange(change)
            }
        }
        
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
    }

    func didObserveChange(_ change: ObjectChange) {
        switch change {
        case .change(_):
            tableView.reloadData()
        case .error(let error):
            presentAlert(error: error)
        case .deleted:
            navigationController?.popViewController(animated: true)
        }
    }
    
    func showPriorityView(at cell: UITableViewCell?) {
        if let cell = cell {
            var rect = cell.convert(cell.bounds, to: tableView)
            rect.origin.y = rect.origin.y - CGFloat(patient.priority.value ?? 0) * rect.size.height
            rect.size.height = rect.size.height * 5
            let priorityView = PriorityView(frame: rect)
            priorityView.delegate = self
            tableView.addSubview(priorityView)
        }
    }

    // MARK: - Navigation
    
    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
        if let navVC = segue.destination as? UINavigationController,
            let vc = navVC.topViewController as? ObservationTableViewController {
            vc.delegate = self
            vc.patient = patient
        }
    }

    // MARK: - AttributeTableViewCellDelegate

    func attributeTableViewCellDidReturn(_ cell: AttributeTableViewCell) {
        var next: UITableViewCell?
        if let indexPath = tableView.indexPath(for: cell) {
            if indexPath.row < tableView.numberOfRows(inSection: indexPath.section) - 1 {
                if let cell = tableView.cellForRow(at: IndexPath(row: indexPath.row + 1, section: indexPath.section)) {
                    next = cell
                }
            }
        }
        if let cell = next, cell.becomeFirstResponder() {
            return
        }
        _ = resignFirstResponder()
    }
    
    // MARK: - ObservationTableViewControllerDelegate
    
    func observationTableViewControllerDidDismiss(_ vc: ObservationTableViewController) {
        dismiss(animated: true, completion: nil)
    }
    
    func observationTableViewController(_ vc: ObservationTableViewController, didSave observation: Observation) {
        if let id = patient.id {
            let task = ApiClient.shared.getPatient(idOrPin: id) { (record, error) in
                if let record = record {
                    if let patient = Patient.instantiate(from: record) as? Patient {
                        let realm = AppRealm.open()
                        try! realm.write {
                            realm.add(patient, update: .modified)
                        }
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    if let error = error {
                        self?.presentAlert(error: error)
                    }
                }
            }
            task.resume()
        }
        dismiss(animated: true, completion: nil)
    }

    // MARK: - PriorityViewDelegate

    func priorityView(_ view: PriorityView, didSelect priority: Int) {
        let patientId = patient.id
        let observation = Observation()
        observation.pin = patient.pin
        observation.priority.value = priority
        let task = ApiClient.shared.createObservation(observation.asJSON()) { [weak self] (record, error) in
            if let record = record {
                if let observation = Observation.instantiate(from: record) as? Observation {
                    let realm = AppRealm.open()
                    try! realm.write {
                        realm.add(observation, update: .modified)
                        if let patient = realm.object(ofType: Patient.self, forPrimaryKey: patientId) {
                            patient.priority.value = priority
                        }
                    }
                }
            }
            DispatchQueue.main.async { [weak self] in
                if let error = error {
                    self?.presentAlert(error: error)
                }
            }
        }
        task.resume()
        view.removeFromSuperview()
    }
    
    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch indexPath.section {
        case Section.portrait.rawValue:
            return 224
        default:
            break
        }
        return super.tableView(tableView, heightForRowAt: indexPath)
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.section {
        case Section.priority.rawValue:
            showPriorityView(at: tableView.cellForRow(at: indexPath))
            tableView.deselectRow(at: indexPath, animated: false)
        case Section.location.rawValue:
            if indexPath.row == 1 {
                if let lat = patient.lat, let lng = patient.lng, lat != "", lng != "" {
                    if let vc = UIStoryboard(name: "Patients", bundle: nil).instantiateViewController(withIdentifier: "Map") as? MapViewController {
                        vc.patient = patient
                        navigationController?.pushViewController(vc, animated: true)
                    }
                }
            }
        default:
            break
        }
    }

    // MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 6
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case Section.location.rawValue:
            return NSLocalizedString("Location", comment: "")
        case Section.info.rawValue:
            return NSLocalizedString("Info", comment: "")
        case Section.vitals.rawValue:
            return NSLocalizedString("Vitals", comment: "")
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case Section.portrait.rawValue:
            return 1
        case Section.priority.rawValue:
            return 1
        case Section.location.rawValue:
            return 2
        case Section.info.rawValue:
            return INFO.count
        case Section.vitals.rawValue:
            return VITALS.count
        default: //// observations
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        switch indexPath.section {
        case Section.portrait.rawValue:
            cell = tableView.dequeueReusableCell(withIdentifier: "Portrait", for: indexPath)
        case Section.priority.rawValue:
            cell = tableView.dequeueReusableCell(withIdentifier: "Priority", for: indexPath)
        case Section.location.rawValue:
            switch indexPath.row {
            case 0:
                cell = tableView.dequeueReusableCell(withIdentifier: "Attribute", for: indexPath)
                if let cell = cell as? AttributeTableViewCell {
                    cell.delegate = self
                    cell.attribute = Patient.Keys.location
                    cell.attributeType = .string
                }
            default:
                cell = tableView.dequeueReusableCell(withIdentifier: "LatLng", for: indexPath)
                if let cell = cell as? LatLngTableViewCell {
                    cell.delegate = self
                }
            }
        default:
            cell = tableView.dequeueReusableCell(withIdentifier: "Attribute", for: indexPath)
            if let cell = cell as? AttributeTableViewCell {
                cell.delegate = self
                switch indexPath.section {
                case Section.info.rawValue:
                    cell.attribute = INFO[indexPath.row]
                    cell.attributeType = INFO_TYPES[indexPath.row]
                case Section.vitals.rawValue:
                    cell.attribute = VITALS[indexPath.row]
                    cell.attributeType = VITALS_TYPES[indexPath.row]
                default:
                    break
                }
            }
        }
        if let cell = cell as? PatientTableViewCell {
            cell.configure(from: patient)
        }
        return cell
    }
}
