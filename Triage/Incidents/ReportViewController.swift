//
//  ReportViewController.swift
//  Triage
//
//  Created by Francis Li on 11/4/21.
//  Copyright © 2021 Francis Li. All rights reserved.
//

import Keyboardy
internal import LLMKit
internal import LLMKitAWSBedrock
import PRKit
import RealmSwift
import RollbarNotifier
import TranscriptionKit
import UIKit

protocol ReportViewControllerDelegate: AnyObject {
    func reportViewControllerNeedsEditing(_ vc: ReportViewController)
    func reportViewControllerNeedsSave(_ vc: ReportViewController)
}

// swiftlint:disable:next force_try
let numbersExpr = try! NSRegularExpression(pattern: #"(^|\s)(\d+)\s(\d+)"#, options: [.caseInsensitive])

class ReportViewController: UIViewController, FormBuilder, FormViewControllerDelegate, FormsViewControllerDelegate,
                            KeyboardAwareScrollViewController, LatLngControlDelegate, LocationViewControllerDelegate,
                            RecordingFieldDelegate, RecordingViewControllerDelegate, TranscriberDelegate {
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var scrollViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var containerView: UIStackView!
    @IBOutlet weak var commandFooter: CommandFooter!
    @IBOutlet weak var recordButton: RecordButton!
    var formInputAccessoryView: UIView!
    var formComponents: [String: PRKit.FormComponent] = [:]
    var destinationFacilityField: PRKit.FormField!
    var agencyField: PRKit.FormField?
    var incidentNumberSpinner: UIActivityIndicatorView?
    var latLngControl: LatLngControl?
    var triageControl: TriageControl?
    var recordingsSection: FormSection!
    var signaturesSection: FormSection!
    var narrativeText: String?

    var report: Report! {
        didSet { observeReport() }
    }
    var notificationToken: NotificationToken?
    var newReport: Report?

    var player: Transcriber?
    var playingRecordingField: RecordingField?

    weak var delegate: ReportViewControllerDelegate?

    deinit {
        notificationToken?.invalidate()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        registerForKeyboardNotifications(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        unregisterFromKeyboardNotifications()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        scrollView.backgroundColor = .background

        if traitCollection.horizontalSizeClass == .regular {
            NSLayoutConstraint.activate([
                containerView.widthAnchor.constraint(equalToConstant: 690)
            ])
        } else {
            NSLayoutConstraint.activate([
                containerView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 20),
                containerView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -20)
            ])
        }

        formInputAccessoryView = FormInputAccessoryView(rootView: view)

        var (section, cols, colA, colB) = newSection()
        var header: UIView
        var tag = 1

        let isMCI = report.scene?.isMCI ?? false
        if isMCI {
            addTextField(source: report, attributeKey: "pin",
                         attributeType: .integer, tag: &tag, to: colA)

            var zero = 0
            destinationFacilityField = newTextField(source: report, attributeKey: "disposition.destinationFacility", tag: &zero)
            destinationFacilityField.attributeValue = report.disposition?.destinationFacility?.displayName as? NSObject
            destinationFacilityField.isEnabled = false
            destinationFacilityField.isEditing = false
            colA.addArrangedSubview(destinationFacilityField)

            agencyField = newTextField(source: report, attributeKey: "response.agency", tag: &zero)
            agencyField?.attributeValue = report.response?.agency?.displayName as? NSObject
            agencyField?.isEnabled = false
            agencyField?.isEditing = false
            colA.addArrangedSubview(agencyField!)

            addTextField(source: report, attributeKey: "response.unitNumber", keyboardType: .numbersAndPunctuation, tag: &tag, to: colA)
            addTextField(source: report, attributeKey: "response.callSign", keyboardType: .default, tag: &tag, to: colA)

            let triageControl = TriageControl()
            triageControl.priority = TriagePriority(rawValue: report.patient?.priority ?? -1)
            triageControl.addTarget(self, action: #selector(triagePriorityChanged(_:)), for: .valueChanged)
            colA.addArrangedSubview(triageControl)
            self.triageControl = triageControl
            addTextField(source: report, attributeKey: "patient.ageArray",
                         attributeType: .integerWithUnit(EnumKeyboardSource<PatientAgeUnits>()),
                         tag: &tag, to: colA)
            addTextField(source: report, attributeKey: "patient.gender",
                         attributeType: .single(EnumKeyboardSource<PatientGender>()),
                         tag: &tag, to: colA)
            addTextField(source: report, attributeKey: "narrative.text", tag: &tag, to: colB)
            let locationField = newTextField(source: report, attributeKey: "patient.location", tag: &tag)
            formComponents["patient.location"] = locationField
            let locationView = UIView()
            locationView.addSubview(locationField)
            NSLayoutConstraint.activate([
                locationField.topAnchor.constraint(equalTo: locationView.topAnchor),
                locationField.leftAnchor.constraint(equalTo: locationView.leftAnchor),
                locationField.rightAnchor.constraint(equalTo: locationView.rightAnchor)
            ])
            let latLngControl = LatLngControl()
            latLngControl.delegate = self
            latLngControl.location = report.patient?.latLng
            latLngControl.translatesAutoresizingMaskIntoConstraints = false
            locationView.addSubview(latLngControl)
            NSLayoutConstraint.activate([
                latLngControl.topAnchor.constraint(equalTo: locationField.bottomAnchor, constant: 4),
                latLngControl.leftAnchor.constraint(equalTo: locationField.leftAnchor, constant: 16),
                latLngControl.rightAnchor.constraint(equalTo: locationField.rightAnchor, constant: -16),
                locationView.bottomAnchor.constraint(equalTo: latLngControl.bottomAnchor)
            ])
            self.latLngControl = latLngControl
            colB.addArrangedSubview(locationView)

            section.addArrangedSubview(cols)
            containerView.addArrangedSubview(section)

            (section, cols, colA, colB) = newSection()
            header = newHeader("ReportViewController.patientInformation".localized,
                               subheaderText: "ReportViewController.optional".localized)
            section.addArrangedSubview(header)
            addTextField(source: report, attributeKey: "patient.firstName", tag: &tag, to: colA)
            addTextField(source: report, attributeKey: "patient.lastName", tag: &tag, to: colB)
            addTextField(source: report, attributeKey: "patient.dob", attributeType: .date, tag: &tag, to: colA)
            section.addArrangedSubview(cols)
            containerView.addArrangedSubview(section)
        } else {
            let innerCols = newColumns()
            innerCols.distribution = .fillProportionally
            innerCols.spacing = 10
            addTextField(source: report, attributeKey: "response.incidentNumber",
                         keyboardType: .numbersAndPunctuation, tag: &tag, to: innerCols)
            if let incidentNumberField = formComponents["response.incidentNumber"] as? PRKit.TextField {
                let incidentNumberSpinner = UIActivityIndicatorView.withMediumStyle()
                incidentNumberSpinner.translatesAutoresizingMaskIntoConstraints = false
                incidentNumberSpinner.color = .base500
                incidentNumberSpinner.hidesWhenStopped = true
                incidentNumberField.contentView.addSubview(incidentNumberSpinner)
                NSLayoutConstraint.activate([
                    incidentNumberSpinner.leftAnchor.constraint(equalTo: incidentNumberField.textView.leftAnchor),
                    incidentNumberSpinner.centerYAnchor.constraint(equalTo: incidentNumberField.textView.centerYAnchor)
                ])
                self.incidentNumberSpinner = incidentNumberSpinner
            }
            let alertButton = PRKit.Button()
            alertButton.style = .destructiveSecondary
            alertButton.setTitle("Button.redAlert".localized, for: .normal)
            alertButton.addTarget(self, action: #selector(mciPressed), for: .touchUpInside)
            alertButton.widthAnchor.constraint(equalToConstant: 110).isActive = true
            innerCols.addArrangedSubview(alertButton)
            colA.addArrangedSubview(innerCols)

            let addressField = CellField()
            addressField.source = report
            addressField.labelText = "Scene.address".localized
            addressField.attributeKey = "scene.address"
            addressField.delegate = self
            addressField.text = report?.scene?.address
            formComponents["scene.address"] = addressField
            colA.addArrangedSubview(addressField)

            addTextField(source: report, attributeKey: "response.unitNumber", keyboardType: .numbersAndPunctuation, tag: &tag, to: colB)
            addTextField(source: report, attributeKey: "response.callSign", keyboardType: .default, tag: &tag, to: colB)
            addTextField(source: report, attributeKey: "narrative.text", tag: &tag, to: colA)
            addTextField(source: report, attributeKey: "time.unitNotifiedByDispatch", attributeType: .datetime, tag: &tag, to: colB)
            addTextField(source: report, attributeKey: "time.arrivedAtPatient", attributeType: .datetime, tag: &tag, to: colB)
            addTextField(source: report, attributeKey: "disposition.unitDisposition",
                         attributeType: .single(EnumKeyboardSource<UnitDisposition>()),
                         tag: &tag, to: colB)
            addTextField(source: report, attributeKey: "disposition.patientEvaluationCare",
                         attributeType: .single(EnumKeyboardSource<PatientEvaluationCare>()),
                         tag: &tag, to: colB)
            addTextField(source: report, attributeKey: "disposition.crewDisposition",
                         attributeType: .single(EnumKeyboardSource<CrewDisposition>()),
                         tag: &tag, to: colB)
            addTextField(source: report, attributeKey: "disposition.transportDisposition",
                         attributeType: .single(EnumKeyboardSource<TransportDisposition>()),
                         tag: &tag, to: colB)
            addTextField(source: report, attributeKey: "disposition.reasonForRefusalRelease",
                         attributeType: .multi(EnumKeyboardSource<ReasonForRefusalRelease>()),
                         tag: &tag, to: colB)

            var zero = 0
            destinationFacilityField = newTextField(source: report, attributeKey: "disposition.destinationFacility", tag: &zero)
            destinationFacilityField.attributeValue = report.disposition?.destinationFacility?.displayName as? NSObject
            destinationFacilityField.isEnabled = false
            destinationFacilityField.isEditing = false
            colB.addArrangedSubview(destinationFacilityField)

            section.addArrangedSubview(cols)
            containerView.addArrangedSubview(section)

            (signaturesSection, cols, colA, colB) = newSection()
            header = newHeader("ReportViewController.signatures".localized)
            signaturesSection.addArrangedSubview(header)
            signaturesSection.addArrangedSubview(cols)
            var prevFormInstanceId: String?
            var formCount = 0
            for (i, signature) in report.signatures.enumerated() {
                if signature.formInstanceId != prevFormInstanceId {
                    addSignaturesField(i, source: report, to: formCount.isMultiple(of: 2) ? colA : colB)
                    prevFormInstanceId = signature.formInstanceId
                    formCount += 1
                }
            }
            let button = newButton(bundleImage: "Plus24px", title: "Button.collectSignatures".localized)
            button.addTarget(self, action: #selector(collectSignaturesPressed(_:)), for: .touchUpInside)
            button.tag = tag
            tag += 1000
            signaturesSection.addLastButton(button)
            containerView.addArrangedSubview(signaturesSection)

            (section, cols, colA, colB) = newSection()
            header = newHeader("ReportViewController.patientInformation".localized,
                               subheaderText: "ReportViewController.optional".localized)
            section.addArrangedSubview(header)
            addTextField(source: report, attributeKey: "patient.firstName", tag: &tag, to: colA)
            addTextField(source: report, attributeKey: "patient.lastName", tag: &tag, to: colB)
            addTextField(source: report, attributeKey: "patient.dob", attributeType: .date, tag: &tag, to: colA)
            addTextField(source: report, attributeKey: "patient.ageArray",
                         attributeType: .integerWithUnit(EnumKeyboardSource<PatientAgeUnits>()),
                         tag: &tag, to: colB)
            addTextField(source: report, attributeKey: "patient.gender",
                         attributeType: .single(EnumKeyboardSource<PatientGender>()),
                         tag: &tag, to: colA)
            section.addArrangedSubview(cols)
            containerView.addArrangedSubview(section)
        }

        (section, cols, colA, colB) = newSection()
        header = newHeader("ReportViewController.medicalInformation".localized,
                           subheaderText: "ReportViewController.optional".localized)
        section.addArrangedSubview(header)
        addTextField(source: report, attributeKey: "situation.chiefComplaint", tag: &tag, to: colA)
        addTextField(source: report, attributeKey: "situation.primarySymptom",
                     attributeType: .custom(NemsisComboKeyboard(
                        field: "eSituation.09",
                        sources: [ICD10CMKeyboardSource()],
                        isMultiSelect: false,
                        negatives: [.notApplicable])),
                     tag: &tag, to: colB)
        addTextField(source: report, attributeKey: "situation.otherAssociatedSymptoms",
                     attributeType: .custom(NemsisComboKeyboard(
                        field: "eSituation.10",
                        sources: [ICD10CMKeyboardSource()],
                        isMultiSelect: true,
                        negatives: [.notApplicable])),
                     tag: &tag, to: colB)
        addTextField(source: report, attributeKey: "history.medicalSurgicalHistory",
                     attributeType: .custom(NemsisComboKeyboard(
                        field: "eHistory.08",
                        sources: [ICD10CMKeyboardSource()],
                        isMultiSelect: true,
                        negatives: [.notApplicable, .noneReported, .refused, .unabletoComplete, .unresponsive])),
                     tag: &tag, to: colA)
        addTextField(source: report, attributeKey: "history.medicationAllergies",
                     attributeType: .custom(NemsisComboKeyboard(
                        field: "eHistory.06",
                        sources: [RxNormKeyboardSource(includeSystem: true)],
                        isMultiSelect: true,
                        negatives: [.notApplicable, .noKnownDrugAllergy, .refused, .unresponsive, .unabletoComplete],
                        includeSystem: true)),
                     tag: &tag, to: colA)
        addTextField(source: report,
                     attributeKey: "history.environmentalFoodAllergies",
                     attributeType: .custom(NemsisKeyboard(
                        field: "eHistory.07",
                        sources: [SNOMEDKeyboardSource()],
                        isMultiSelect: true)),
                     tag: &tag, to: colB)
        section.addArrangedSubview(cols)
        containerView.addArrangedSubview(section)

        for i in 0..<max(1, report.vitals.count) {
            (section, cols, colA, colB) = newVitalsSection(i, source: report, tag: &tag)
            containerView.addArrangedSubview(section)
        }
        var button = newButton(bundleImage: "Plus24px", title: "Button.newVitals".localized)
        button.addTarget(self, action: #selector(newVitalsPressed(_:)), for: .touchUpInside)
        button.tag = tag
        section.addLastButton(button)

        tag += 10000
        for i in 0..<max(1, report.procedures.count) {
            (section, cols, colA, colB) = newProceduresSection(i, source: report, tag: &tag)
            containerView.addArrangedSubview(section)
        }
        button = newButton(bundleImage: "Plus24px", title: "Button.addProcedure".localized)
        button.addTarget(self, action: #selector(addProcedurePressed), for: .touchUpInside)
        button.tag = tag
        section.addLastButton(button)

        tag += 10000
        for i in 0..<max(1, report.medications.count) {
            (section, cols, colA, colB) = newMedicationsSection(i, source: report, tag: &tag)
            containerView.addArrangedSubview(section)
        }
        button = newButton(bundleImage: "Plus24px", title: "Button.addMedication".localized)
        button.addTarget(self, action: #selector(addMedicationPressed), for: .touchUpInside)
        button.tag = tag
        section.addLastButton(button)

        (recordingsSection, cols, colA, colB) = newSection()
        header = newHeader("ReportViewController.recordings".localized)
        recordingsSection.addArrangedSubview(header)
        for i in 0..<report.files.count {
            addRecordingField(i, source: report, to: i.isMultiple(of: 2) ? colA : colB)
        }
        recordingsSection.addArrangedSubview(cols)
        containerView.addArrangedSubview(recordingsSection)

        updateFormFieldVisibility()

        setEditing(isEditing, animated: false)
    }

    func observeReport() {
        notificationToken?.invalidate()
        if report.response?.incidentNumber?.isEmpty ?? true {
            if report.response?.realm != nil {
                incidentNumberSpinner?.startAnimating()
                notificationToken = report.response?.observe { [weak self] (change) in
                    switch change {
                    case .change:
                        self?.refreshFormFieldsAndControls(["response.incidentNumber"])
                        if !(self?.report.response?.incidentNumber?.isEmpty ?? true) {
                            self?.incidentNumberSpinner?.stopAnimating()
                        }
                    case .error(let error):
                        self?.presentAlert(error: error)
                    case .deleted:
                        self?.dismissAnimated()
                    }
                }
            }
        }
    }

    func addRecordingField(_ i: Int, source: Report? = nil, target: Report? = nil, to col: UIStackView) {
        let report = target ?? source
        let file = report?.files[i]
        let recordingField = RecordingField()
        recordingField.source = source
        recordingField.target = target
        recordingField.attributeKey = "files[\(i)]"
        recordingField.delegate = self
        recordingField.setDate(file?.createdAt ?? Date())
        recordingField.titleText = String(format: "ReportViewController.recording".localized, i + 1)
        recordingField.durationText = file?.metadata?["formattedDuration"] as? String ?? "--:--"
        if let sources = report?.predictions?["_sources"] as? [String: [String: Any]] {
            for source in sources.values {
                if (source["isFinal"] as? Bool) ?? false, (source["fileId"] as? String)?.lowercased() == file?.canonicalId?.lowercased() {
                    recordingField.text = source["text"] as? String
                    break
                }
            }
        }
        col.addArrangedSubview(recordingField)
    }

    func addSignaturesField(_ i: Int, source: Report? = nil, target: Report? = nil, to col: UIStackView) {
        let report = target ?? source
        let signature = report?.signatures[i]
        let signaturesField = CellField()
        signaturesField.isLabelHidden = true
        signaturesField.source = source
        signaturesField.target = target
        signaturesField.attributeKey = "signatures[\(i)]"
        signaturesField.delegate = self
        signaturesField.text = signature?.form?.title
        col.addArrangedSubview(signaturesField)
    }

    func newVitalsSection(_ i: Int, source: Report? = nil, target: Report? = nil,
                          tag: inout Int) -> (FormSection, UIStackView, UIStackView, UIStackView) {
        let (section, cols, colA, colB) = newSection()
        section.type = Vital.self
        section.index = i

        let header = newHeader("ReportViewController.vitals".localized,
                               subheaderText: "ReportViewController.optional".localized)
        section.addArrangedSubview(header)
        addTextField(source: source, target: target,
                     attributeKey: "vitals[\(i)].vitalSignsTakenAt", attributeType: .datetime, tag: &tag, to: colA)
        let innerCols = newColumns()
        innerCols.distribution = .fillProportionally
        innerCols.spacing = 5
        addTextField(source: source, target: target,
                     attributeKey: "vitals[\(i)].bpSystolic", attributeType: .integer, tag: &tag, to: innerCols)
        let label = UILabel()
        label.font = .h3SemiBold
        label.textColor = .base800
        label.text = "/"
        innerCols.addArrangedSubview(label)
        addTextField(source: source, target: target,
                     attributeKey: "vitals[\(i)].bpDiastolic", attributeType: .integer, tag: &tag, to: innerCols)
        colB.addArrangedSubview(innerCols)
        addTextField(source: source, target: target,
                     attributeKey: "vitals[\(i)].heartRate", attributeType: .integer, unitText: " bpm", tag: &tag, to: colA)
        addTextField(source: source, target: target,
                     attributeKey: "vitals[\(i)].respiratoryRate", attributeType: .integer, unitText: " bpm", tag: &tag, to: colB)
        addTextField(source: source, target: target,
                     attributeKey: "vitals[\(i)].bloodGlucoseLevel", attributeType: .integer, tag: &tag, to: colA)
        addTextField(source: source, target: target,
                     attributeKey: "vitals[\(i)].cardiacRhythm",
                     attributeType: .custom(NemsisComboKeyboard(
                        source: EnumKeyboardSource<VitalCardiacRhythm>(),
                        isMultiSelect: true,
                        negatives: [
                            .notApplicable,
                            .refused,
                            .unabletoComplete
                        ])),
                     tag: &tag, to: colB)
        addTextField(source: source, target: target,
                     attributeKey: "vitals[\(i)].totalGlasgowComaScore", attributeType: .integer, tag: &tag, to: colA)
        addTextField(source: source, target: target,
                     attributeKey: "vitals[\(i)].pulseOximetry", attributeType: .integer, unitText: " %", tag: &tag, to: colB)
        addTextField(source: source, target: target,
                     attributeKey: "vitals[\(i)].endTidalCarbonDioxide", attributeType: .decimal, tag: &tag, to: colA)
        addTextField(source: source, target: target,
                     attributeKey: "vitals[\(i)].carbonMonoxide", attributeType: .decimal, unitText: " %", tag: &tag, to: colB)
        section.addArrangedSubview(cols)
        return (section, cols, colA, colB)
    }

    func newProceduresSection(_ i: Int, source: Report? = nil, target: Report? = nil,
                              tag: inout Int) -> (FormSection, UIStackView, UIStackView, UIStackView) {
        let (section, cols, colA, colB) = newSection()
        section.type = Procedure.self
        section.index = i

        let header = newHeader("ReportViewController.procedures".localized,
                               subheaderText: "ReportViewController.optional".localized)
        section.addArrangedSubview(header)
        addTextField(source: source, target: target,
                     attributeKey: "procedures[\(i)].performedAt", attributeType: .datetime, tag: &tag, to: colA)
        addTextField(source: source, target: target,
                     attributeKey: "procedures[\(i)].procedure",
                     attributeType: .custom(NemsisComboKeyboard(
                        field: "eProcedures.03",
                        sources: [SNOMEDKeyboardSource()],
                        isMultiSelect: false,
                        negatives: [
                            .notApplicable, .contraindicationNoted, .deniedByOrder, .refused, .unabletoComplete, .orderCriteriaNotMet
                        ],
                        isNegativeExclusive: false)),
                     tag: &tag, to: colB)
        addTextField(source: source, target: target,
                     attributeKey: "procedures[\(i)].successful",
                     attributeType: .custom(NemsisComboKeyboard(
                        source: EnumKeyboardSource<NemsisBoolean>(),
                        isMultiSelect: false,
                        negatives: [
                            .notApplicable
                        ])),
                     tag: &tag, to: colB)
        addTextField(source: source, target: target,
                     attributeKey: "procedures[\(i)].responseToProcedure",
                     attributeType: .custom(NemsisComboKeyboard(
                        source: EnumKeyboardSource<ProcedureResponse>(),
                        isMultiSelect: false,
                        negatives: [
                            .notApplicable
                        ])),
                     tag: &tag, to: colB)
        section.addArrangedSubview(cols)
        return (section, cols, colA, colB)
    }

    func newMedicationsSection(_ i: Int, source: Report? = nil, target: Report? = nil,
                               tag: inout Int) -> (FormSection, UIStackView, UIStackView, UIStackView) {
        let (section, cols, colA, colB) = newSection()
        section.type = Medication.self
        section.index = i

        let header = newHeader("ReportViewController.medications".localized,
                               subheaderText: "ReportViewController.optional".localized)
        section.addArrangedSubview(header)
        addTextField(source: source, target: target,
                     attributeKey: "medications[\(i)].administeredAt", attributeType: .datetime, tag: &tag, to: colA)
        addTextField(source: source, target: target,
                     attributeKey: "medications[\(i)].medication",
                     attributeType: .custom(NemsisComboKeyboard(
                        field: "eMedications.03",
                        sources: [RxNormKeyboardSource(includeSystem: true)],
                        isMultiSelect: false,
                        negatives: [
                            .notApplicable, .contraindicationNoted, .deniedByOrder, .medicationAllergy, .medicationAlreadyTaken,
                            .refused, .unabletoComplete, .orderCriteriaNotMet
                        ],
                        isNegativeExclusive: false,
                        includeSystem: true)),
                     tag: &tag, to: colA)
        addTextField(source: source, target: target,
                     attributeKey: "medications[\(i)].administeredRoute",
                     attributeType: .custom(NemsisComboKeyboard(
                        source: EnumKeyboardSource<MedicationAdministrationRoute>(),
                        isMultiSelect: false,
                        negatives: [
                            .notApplicable,
                            .unabletoComplete
                        ])),
                     tag: &tag, to: colB)
        addTextField(source: source, target: target,
                     attributeKey: "medications[\(i)].dosage",
                     attributeType: .decimal,
                     tag: &tag, to: colB)
        addTextField(source: source, target: target,
                     attributeKey: "medications[\(i)].dosageUnits",
                     attributeType: .custom(NemsisComboKeyboard(
                        source: EnumKeyboardSource<MedicationDosageUnits>(),
                        isMultiSelect: false,
                        negatives: [
                            .notApplicable
                        ])),
                     tag: &tag, to: colB)
        addTextField(source: source, target: target,
                     attributeKey: "medications[\(i)].responseToMedication",
                     attributeType: .custom(NemsisComboKeyboard(
                        source: EnumKeyboardSource<MedicationResponse>(),
                        isMultiSelect: false,
                        negatives: [
                            .notApplicable
                        ])),
                     tag: &tag, to: colA)
        section.addArrangedSubview(cols)
        return (section, cols, colA, colB)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for formField in formComponents.values {
            formField.updateStyle()
        }
        destinationFacilityField.updateStyle()
        agencyField?.updateStyle()
        var contentInset = scrollView.contentInset
        contentInset.bottom = commandFooter.frame.height + 16
        scrollView.contentInset = contentInset
    }

    func removeSections(type: AnyClass, greaterThan count: Int) {
        var lastSection: FormSection?
        for view in containerView.arrangedSubviews {
            if let section = view as? FormSection, section.type == type {
                if section.index ?? 0 >= count {
                    for formField in FormSection.fields(in: section) {
                        if let attributeKey = formField.attributeKey {
                            formComponents.removeValue(forKey: attributeKey)
                        }
                    }
                    if let button = section.findLastButton() {
                        button.removeFromSuperview()
                        lastSection?.addLastButton(button)
                    }
                    section.removeFromSuperview()
                } else {
                    lastSection = section
                }
            }
        }
    }

    func disableEditing() {
        commandFooter.isHidden = true
        triageControl?.updateButton.isEnabled = false
        for view in containerView.arrangedSubviews {
            if let section = view as? FormSection {
                if let button = section.findLastButton() {
                    button.isHidden = true
                }
            }
        }
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        if editing {
            if report.realm != nil {
                newReport = Report(clone: report)
            } else {
                newReport = report
            }
        } else if let newReport = newReport {
            if newReport.vitals.count > report.vitals.count {
                removeSections(type: Vital.self, greaterThan: max(1, report.vitals.count))
            }
            if newReport.procedures.count > report.procedures.count {
                removeSections(type: Procedure.self, greaterThan: max(1, report.procedures.count))
            }
            if newReport.medications.count > report.medications.count {
                removeSections(type: Medication.self, greaterThan: max(1, report.medications.count))
            }
            if newReport.files.count > report.files.count {
                var recordingFields: [RecordingField] = []
                FormSection.subviews(&recordingFields, in: recordingsSection)
                for recordingField in recordingFields[report.files.count..<newReport.files.count] {
                    recordingField.removeFromSuperview()
                }
            }
            if newReport.signatures.count != report.signatures.count {
                // signatures can be deleted, so brute force reconstruct this section
                var signatureFields: [CellField] = []
                FormSection.subviews(&signatureFields, in: signaturesSection)
                for signatureField in signatureFields {
                    signatureField.removeFromSuperview()
                }
                let button = signaturesSection.findLastButton()
                button?.removeFromSuperview()
                var prevFormInstanceId: String?
                var formCount = 0
                for (i, signature) in report.signatures.enumerated() {
                    if signature.formInstanceId != prevFormInstanceId {
                        addSignaturesField(i, source: report, to: formCount.isMultiple(of: 2) ? signaturesSection.colA : signaturesSection.colB)
                        prevFormInstanceId = signature.formInstanceId
                        formCount += 1
                    }
                }
                if let button = button {
                    signaturesSection.addLastButton(button)
                }
            }
            self.newReport = nil
        }
        for formField in formComponents.values {
            formField.isEditing = editing
            formField.isEnabled = editing
            formField.target = newReport
            if !editing {
                _ = formField.resignFirstResponder()
            }
        }
        // handle special case controls
        latLngControl?.isEditing = editing
        // for brand new reports during an MCI, immedialy initiate location capture
        if editing && (report.scene?.isMCI ?? false) && report.realm == nil {
            latLngControl?.capturePressed()
        }
    }

    func resetFormFields() {
        for formComponent in formComponents.values {
            if let attributeKey = formComponent.attributeKey {
                formComponent.attributeValue = formComponent.source?.value(forKeyPath: attributeKey) as? NSObject
                if let formField = formComponent as? PRKit.FormField, let source = formField.source as? Predictions {
                    formField.status = source.predictionStatus(for: attributeKey)
                }
            }
        }
        destinationFacilityField.attributeValue = report.disposition?.destinationFacility?.displayName as? NSObject
        agencyField?.attributeValue = report.response?.agency?.displayName as? NSObject
        updateFormFieldVisibility()
    }

    func refreshFormFieldsAndControls(_ attributeKeys: [String]? = nil) {
        refreshFormFields(attributeKeys: attributeKeys)
        // if mci, update triage control
        if let triageControl = triageControl {
            triageControl.priority = TriagePriority(rawValue: newReport?.patient?.priority ?? -1)
        }
    }

    func updateFormFieldVisibility() {
        destinationFacilityField.isHidden = destinationFacilityField.attributeValue == nil
        if report.scene?.isMCI ?? false {
            agencyField?.isHidden = agencyField?.attributeValue == nil
            formComponents["response.unitNumber"]?.isHidden = destinationFacilityField.attributeValue == nil
            formComponents["response.callSign"]?.isHidden = destinationFacilityField.attributeValue == nil
        }
        if let unitDisposition = (newReport ?? report)?.disposition?.unitDisposition, unitDisposition == UnitDisposition.patientContactMade.rawValue {
            formComponents["disposition.patientEvaluationCare"]?.isHidden = false
            formComponents["disposition.crewDisposition"]?.isHidden = false
            formComponents["disposition.transportDisposition"]?.isHidden = false
        } else {
            formComponents["disposition.patientEvaluationCare"]?.isHidden = true
            formComponents["disposition.crewDisposition"]?.isHidden = true
            formComponents["disposition.transportDisposition"]?.isHidden = true
        }
        if let patientEvaluationCare = (newReport ?? report)?.disposition?.patientEvaluationCare,
           patientEvaluationCare == PatientEvaluationCare.patientEvaluatedRefusedCare.rawValue ||
            patientEvaluationCare == PatientEvaluationCare.patientRefused.rawValue {
            formComponents["disposition.reasonForRefusalRelease"]?.isHidden = false
        } else if let transportDisposition = (newReport ?? report)?.disposition?.transportDisposition,
                  transportDisposition == TransportDisposition.patientRefusedTransport.rawValue {
            formComponents["disposition.reasonForRefusalRelease"]?.isHidden = false
        } else {
            formComponents["disposition.reasonForRefusalRelease"]?.isHidden = true
        }
    }

    @objc func collectSignaturesPressed(_ button: PRKit.Button) {
        if !isEditing {
            guard let delegate = delegate else { return }
            delegate.reportViewControllerNeedsEditing(self)
        }
        guard newReport != nil else { return }
        let vc = UIStoryboard(name: "Incidents", bundle: nil).instantiateViewController(withIdentifier: "Forms")
        if let vc = vc as? FormsViewController {
            vc.delegate = self
        }
        let navVC = UINavigationController(rootViewController: vc)
        navVC.modalPresentationStyle = .fullScreen
        navVC.isNavigationBarHidden = true
        presentAnimated(navVC)
    }

    @objc func newVitalsPressed(_ button: PRKit.Button) {
        if !isEditing {
            guard let delegate = delegate else { return }
            delegate.reportViewControllerNeedsEditing(self)
        }
        guard let newReport = newReport else { return }
        let vital = Vital.newRecord()
        let i = newReport.vitals.count
        var tag = button.tag
        newReport.vitals.append(vital)

        guard let prevSection = FormSection.parent(of: button) else { return }
        guard let prevIndex = containerView.arrangedSubviews.firstIndex(of: prevSection) else { return }

        let (section, _, _, _) = newVitalsSection(i, target: newReport, tag: &tag)
        containerView.insertArrangedSubview(section, at: prevIndex + 1)
        button.tag = tag
        button.removeFromSuperview()
        section.addLastButton(button)
    }

    @objc func addProcedurePressed(_ button: PRKit.Button) {
        if !isEditing {
            guard let delegate = delegate else { return }
            delegate.reportViewControllerNeedsEditing(self)
        }
        guard let newReport = newReport else { return }
        let procedure = Procedure.newRecord()
        let i = newReport.procedures.count
        var tag = button.tag
        newReport.procedures.append(procedure)

        guard let prevSection = FormSection.parent(of: button) else { return }
        guard let prevIndex = containerView.arrangedSubviews.firstIndex(of: prevSection) else { return }

        let (section, _, _, _) = newProceduresSection(i, target: newReport, tag: &tag)
        containerView.insertArrangedSubview(section, at: prevIndex + 1)
        button.tag = tag
        button.removeFromSuperview()
        section.addLastButton(button)
    }

    @objc func addMedicationPressed(_ button: PRKit.Button) {
        if !isEditing {
            guard let delegate = delegate else { return }
            delegate.reportViewControllerNeedsEditing(self)
        }
        guard let newReport = newReport else { return }
        let medication = Medication.newRecord()
        let i = newReport.medications.count
        var tag = button.tag
        newReport.medications.append(medication)

        guard let prevSection = FormSection.parent(of: button) else { return }
        guard let prevIndex = containerView.arrangedSubviews.firstIndex(of: prevSection) else { return }

        let (section, _, _, _) = newMedicationsSection(i, target: newReport, tag: &tag)
        containerView.insertArrangedSubview(section, at: prevIndex + 1)
        button.tag = tag
        button.removeFromSuperview()
        section.addLastButton(button)
    }

    @IBAction func recordPressed() {
        if !isEditing {
            guard let delegate = delegate else { return }
            delegate.reportViewControllerNeedsEditing(self)
        }
        narrativeText = newReport?.narrative?.text
        performSegue(withIdentifier: "Record", sender: self)
    }

    @objc func mciPressed() {
        let modal = ModalViewController()
        modal.isDismissedOnAction = false
        modal.messageText = "ReportViewController.redAlert.message".localized
        modal.addAction(UIAlertAction(title: "Button.startMCI".localized, style: .destructive, handler: { [weak self] (_) in
            guard let self = self else { return }
            AppRealm.startScene(report: self.report) { [weak self] (canonicalId, error) in
                DispatchQueue.main.async {
                    modal.dismiss(animated: true)
                }
                if let canonicalId = canonicalId {
                    AppSettings.sceneId = canonicalId
                    if let error = error {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.presentAlert(error: error)
                        }
                    } else {
                        DispatchQueue.main.async {
                            AppDelegate.enterScene(id: canonicalId)
                        }
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.presentAlert(error: ApiClientError.unexpected)
                    }
                }
            }
        }))
        modal.addAction(UIAlertAction(title: "Button.cancel".localized, style: .cancel))
        presentAnimated(modal)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let vc = segue.destination as? RecordingViewController {
            vc.delegate = self
        }
    }

    @objc func triagePriorityChanged(_ sender: TriageControl) {
        if !isEditing {
            newReport = Report(clone: report)
        }
        newReport?.patient?.priority = sender.priority?.rawValue
        if newReport?.disposition?.destinationFacility == nil {
            newReport?.filterPriority = newReport?.patient?.priority
        }
        if !isEditing {
            delegate?.reportViewControllerNeedsSave(self)
        }
    }

    // MARK: - FormFieldDelegate

    func formComponentDidChange(_ component: PRKit.FormComponent) {
        if let field = component as? PRKit.FormField, let attributeKey = field.attributeKey, let target = field.target {
            target.setValue(field.attributeValue, forKeyPath: attributeKey)
            // some hard-coded field visibility rules, until a more generalized implementation can be designed
            switch attributeKey {
            case "patient.dob":
                // calculate age
                if let dob = ISO8601DateFormatter.date(from: field.attributeValue) {
                    let (years, months, days) = dob.age
                    if years > 0 {
                        newReport?.patient?.age = years
                        newReport?.patient?.ageUnits = PatientAgeUnits.years.rawValue
                    } else if months > 0 {
                        newReport?.patient?.age = months
                        newReport?.patient?.ageUnits = PatientAgeUnits.months.rawValue
                    } else {
                        newReport?.patient?.age = days
                        newReport?.patient?.ageUnits = PatientAgeUnits.days.rawValue
                    }
                    refreshFormFieldsAndControls(["patient.ageArray"])
                }
            case "time.arrivedAtPatient":
                // if arrived at patient, set unit disposition to Patient Contact Made automatically if not already set
                if field.attributeValue != nil, newReport?.disposition?.unitDisposition == nil {
                    newReport?.disposition?.unitDisposition = UnitDisposition.patientContactMade.rawValue
                    refreshFormFieldsAndControls(["disposition.unitDisposition"])
                }
                updateFormFieldVisibility()
            case "disposition.unitDisposition":
                if UnitDisposition.patientContactMade.rawValue != field.attributeValue as? String {
                    // clear and hide patient/crew/transport/refusal disposition fields
                    newReport?.disposition?.patientEvaluationCare = nil
                    newReport?.disposition?.crewDisposition = nil
                    newReport?.disposition?.transportDisposition = nil
                    newReport?.disposition?.reasonForRefusalRelease = nil
                    refreshFormFieldsAndControls(["disposition.patientEvaluationCare", "disposition.crewDisposition",
                                       "disposition.transportDisposition", "disposition.reasonForRefusalRelease"])
                }
                updateFormFieldVisibility()
            case "disposition.patientEvaluationCare", "disposition.transportDisposition":
                if newReport?.disposition?.patientEvaluationCare != PatientEvaluationCare.patientEvaluatedRefusedCare.rawValue &&
                    newReport?.disposition?.patientEvaluationCare != PatientEvaluationCare.patientRefused.rawValue &&
                    newReport?.disposition?.transportDisposition != TransportDisposition.patientRefusedTransport.rawValue {
                    newReport?.disposition?.reasonForRefusalRelease = nil
                    refreshFormFieldsAndControls(["disposition.reasonForRefusalRelease"])
                }
                updateFormFieldVisibility()
            default:
                break
            }
        }
    }

    func formFieldDidPress(_ field: PRKit.FormField) {
        if let attributeKey = field.attributeKey {
            if attributeKey.hasPrefix("signatures[") {
                if let report = newReport ?? report, let signature = report.value(forKeyPath: attributeKey) as? Signature, let form = signature.form {
                    let vc = UIStoryboard(name: "Incidents", bundle: nil).instantiateViewController(withIdentifier: "Form")
                    if let vc = vc as? FormViewController {
                        vc.modalPresentationStyle = .fullScreen
                        vc.form = form
                        let newReport = Report.newRecord()
                        newReport.signatures.append(objectsIn: report.signatures.filter { $0.formInstanceId == signature.formInstanceId })
                        vc.report = report
                        vc.isEditing = isEditing
                        if !isEditing {
                            vc.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Button.done".localized, style: .plain, target: self, action: #selector(dismissAnimated))
                        }
                        vc.delegate = self
                        presentAnimated(vc)
                    }
                }
            } else if attributeKey == "scene.address" {
                let vc = UIStoryboard(name: "Incidents", bundle: nil).instantiateViewController(withIdentifier: "Location")
                if let vc = vc as? LocationViewController {
                    vc.delegate = self
                    vc.scene = report.scene
                    vc.newScene = newReport?.scene
                    _ = vc.view
                    vc.isEditing = isEditing
                }
                navigationController?.pushViewController(vc, animated: true)
            }
        }
    }

    func formField(_ field: PRKit.FormField, wantsToPresent vc: UIViewController) {
        presentAnimated(vc)
    }

    // MARK: - FormViewControllerDelegate

    func formViewController(_ vc: FormViewController, didCollect signatures: [Signature]) {
        dismissAnimated()
    }

    func formViewController(_ vc: FormViewController, didDelete signatures: [Signature]) {
        guard let formInstanceId = signatures.first?.formInstanceId else { return }
        if let newReport = newReport {
            // remove the corresponding field
            var cellFields: [CellField] = []
            FormSection.subviews(&cellFields, in: signaturesSection)
            for cellField in cellFields {
                if let attributeKey = cellField.attributeKey,
                   let signature = newReport.value(forKeyPath: attributeKey) as? Signature,
                   signature.formInstanceId == formInstanceId {
                    cellField.removeFromSuperview()
                    break
                }
            }
            // remove all the signatures from the target object
            var newSignatures = Array(newReport.signatures)
            newSignatures.removeAll(where: { signatures.contains($0) })
            newReport.signatures.removeAll()
            newReport.signatures.append(objectsIn: newSignatures)
        }
        dismissAnimated()
    }

    // MARK: - FormsViewControllerDelegate

    func formsViewController(_ vc: FormsViewController, didCollect signatures: [Signature]) {
        dismissAnimated()
        if let newReport = newReport {
            let i = newReport.signatures.count
            var formCount = 0
            var prevFormInstanceId: String?
            for signature in newReport.signatures {
                if signature.formInstanceId != prevFormInstanceId {
                    prevFormInstanceId = signature.formInstanceId
                    formCount += 1
                }
            }
            newReport.signatures.append(objectsIn: signatures)

            let button = signaturesSection.findLastButton()
            button?.removeFromSuperview()
            addSignaturesField(i, source: report, target: newReport, to: formCount.isMultiple(of: 2) ? signaturesSection.colA : signaturesSection.colB)
            if let button = button {
                signaturesSection.addLastButton(button)
            }
        }
    }

    // MARK: - LatLngControlDelegate

    func latLngControlMapPressed(_ control: LatLngControl) {
        let vc = UIStoryboard(name: "Incidents", bundle: nil).instantiateViewController(withIdentifier: "ReportMap")
        if let vc = vc as? ReportMapViewController {
            vc.report = newReport ?? report
        }
        presentAnimated(vc)
    }

    func latLngControlDidCaptureLocation(_ control: LatLngControl) {
        newReport?.patient?.latLng = control.location
    }

    // MARK: - LocationViewControllerDelegate

    func locationViewControllerDidChange(_ vc: LocationViewController) {
        refreshFormFieldsAndControls(["scene.address"])
    }

    // MARK: - RecordingFieldDelegate

    func recordingField(_ field: RecordingField, didPressPlayButton button: UIButton) {
        let startPlaying = !field.isPlaying
        if field != playingRecordingField || field.isPlaying {
            playingRecordingField?.durationText = player?.recordingLengthFormatted
            playingRecordingField?.isPlaying = false
            playingRecordingField = nil
            player?.stopPressed()
        }
        if startPlaying {
            if player == nil {
                player = Transcriber()
                player?.delegate = self
            }
            if let keyPath = field.attributeKey, let file = (field.target ?? field.source)?.value(forKeyPath: keyPath) as? File,
               let fileUrl = file.fileUrl ?? file.file {
                field.isActivityIndicatorAnimating = true
                AppCache.cachedFile(from: fileUrl) { [weak self] (url, error) in
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        field.isActivityIndicatorAnimating = false
                        if let error = error {
                            self.presentAlert(error: error)
                        } else if let url = url {
                            do {
                                self.player?.fileURL = url
                                try self.player?.playPressed()
                                self.playingRecordingField = field
                                field.durationText = "00:00:00"
                                field.isPlaying = true
                            } catch {
                                self.presentAlert(error: error)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - RecordingViewControllerDelegate

    func recordingViewController(_ vc: RecordingViewController, didRecognizeText text: String,
                                 fileId: String, transcriptId: String, metadata: [String: Any], isFinal: Bool) {
        // fix weird number handling from AWS Transcribe (i.e. one-twenty recognized as "1 20" instead of "120")
        let processedText = numbersExpr.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.count),
                                                                 withTemplate: "$1$2$3")
        newReport?.narrative?.text = "\(narrativeText ?? "") \(processedText)".trimmingCharacters(in: .whitespacesAndNewlines)
        let formField = formComponents["narrative.text"]
        formField?.attributeValue = newReport?.narrative?.text as NSObject?
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            self?.newReport?.extractValues(from: processedText, fileId: fileId, transcriptId: transcriptId,
                                           metadata: metadata, isFinal: isFinal)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.refreshFormFieldsAndControls()
                if isFinal {
                    // update recording field with text
                    var recordingFields: [RecordingField] = []
                    FormSection.subviews(&recordingFields, in: self.recordingsSection)
                    for recordingField in recordingFields {
                        if let keyPath = recordingField.attributeKey,
                           let file = (recordingField.target ?? recordingField.source)?.value(forKeyPath: keyPath) as? File,
                           file.canonicalId == fileId {
                            recordingField.text = text
                            break
                        }
                    }
                }
            }
        }
    }

    func recordingViewController(_ vc: RecordingViewController, didFinishRecording fileId: String, fileURL: URL,
                                 duration: TimeInterval, formattedDuration: String) {
        // check for a chief complaint, if none, dispatch to LLM
        if newReport?.situation?.chiefComplaint?.isEmpty ?? true, let text = newReport?.narrative?.text, let awsCredentials = AppSettings.awsCredentials {
            AWSBedrockBot.configure(region: "us-west-2",
                                          accessKeyId: awsCredentials["AccessKeyId"] ?? "",
                                          secretAccessKey: awsCredentials["SecretAccessKey"] ?? "",
                                          sessionToken: awsCredentials["SessionToken"])
            if let bot = BotFactory.instantiate(for: Model(type: .awsBedrock,
                                                           id: "us.meta.llama3-3-70b-instruct-v1:0",
                                                           name: "AWS Bedrock US Meta Llama 3.3 70B Instruct",
                                                           template: .llama3("You are an expert medical secretary."))) {
                Task {
                    do {
                        let response = try await bot.respond(to: "Extract the chief complaint from the following text and return JSON only: \"\(text)\"", isStreaming: false)
                        if let json = response.asJSON(), let value = json["chief_complaint"] as? String {
                            await MainActor.run {
                                newReport?.setValue(value, forKeyPath: "situation.chiefComplaint")
                                refreshFormFieldsAndControls(["situation.chiefComplaint"])
                            }
                        }
                    } catch let error {
                        Rollbar.errorError(error)
                    }
                }
            }
        }

        let file = File.newRecord()
        file.canonicalId = fileId
        file.file = fileURL.lastPathComponent
        file.fileUrl = fileURL.absoluteString
        file.fileAttachmentType = fileURL.pathExtension
        file.externalElectronicDocumentType = FileDocumentType.otherAudioRecording.rawValue
        file.metadata = [
            "duration": duration,
            "formattedDuration": formattedDuration
        ]
        if let newReport = newReport {
            let i = newReport.files.count
            newReport.files.append(file)
            AppRealm.uploadFile(fileURL: fileURL)
            addRecordingField(i, target: newReport, to: i.isMultiple(of: 2) ? recordingsSection.colA : recordingsSection.colB)
        }
    }

    func recordingViewController(_ vc: RecordingViewController, didThrowError error: Error) {
        switch error {
        case TranscriberError.speechRecognitionNotAuthorized:
            // even with speech recognition off, we can still allow a recording...
            vc.startRecording()
        default:
            dismiss(animated: true) { [weak self] in
                self?.presentAlert(error: error)
            }
        }
    }

    // MARK: - TranscriberDelegate

    func transcriber(_ transcriber: Transcriber, didFinishPlaying successfully: Bool) {
        DispatchQueue.main.async { [weak self] in
            if let playingRecordingField = self?.playingRecordingField {
                playingRecordingField.durationText = transcriber.recordingLengthFormatted
                playingRecordingField.isPlaying = false
                self?.playingRecordingField = nil
            }
        }
    }

    func transcriber(_ transcriber: Transcriber, didPlay seconds: TimeInterval, formattedDuration duration: String) {
        DispatchQueue.main.async { [weak self] in
            if let playingRecordingField = self?.playingRecordingField {
                playingRecordingField.durationText = duration
            }
        }
    }
}
