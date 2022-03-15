//
//  ReportViewController.swift
//  Triage
//
//  Created by Francis Li on 11/4/21.
//  Copyright © 2021 Francis Li. All rights reserved.
//

import Keyboardy
import PRKit
import RealmSwift
import TranscriptionKit
import UIKit

protocol ReportViewControllerDelegate: AnyObject {
    func reportViewControllerNeedsEditing(_ vc: ReportViewController)
}

// swiftlint:disable:next force_try
let numbersExpr = try! NSRegularExpression(pattern: #"(^|\s)(\d+)\s(\d+)"#, options: [.caseInsensitive])

class ReportViewController: UIViewController, FormViewController, KeyboardAwareScrollViewController, RecordingFieldDelegate,
                            RecordingViewControllerDelegate, TranscriberDelegate {
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var scrollViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var containerView: UIStackView!
    @IBOutlet weak var commandFooter: CommandFooter!
    @IBOutlet weak var recordButton: RecordButton!
    var formInputAccessoryView: UIView!
    var formFields: [PRKit.FormField] = []
    var recordingsSection: FormSection!

    var report: Report!
    var newReport: Report?

    var player: Transcriber?
    var playingRecordingField: RecordingField?

    weak var delegate: ReportViewControllerDelegate?

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

        var (section, cols, colA, colB) = newSection()
        var tag = 1
        formInputAccessoryView = FormInputAccessoryView(rootView: view)
        addTextField(source: report, attributeKey: "response.incidentNumber",
                     keyboardType: .numbersAndPunctuation, tag: &tag, to: colA)
        addTextField(source: report, attributeKey: "scene.address", tag: &tag, to: colA)
        addTextField(source: report, attributeKey: "response.unitNumber", keyboardType: .numbersAndPunctuation, tag: &tag, to: colB)
        addTextField(source: report, attributeKey: "time.unitNotifiedByDispatch", attributeType: .datetime, tag: &tag, to: colB)
        addTextField(source: report, attributeKey: "time.arrivedAtPatient", attributeType: .datetime, tag: &tag, to: colB)
        addTextField(source: report, attributeKey: "narrative.text", tag: &tag, to: colA)
        addTextField(source: report, attributeKey: "disposition.unitDisposition",
                     attributeType: .single(EnumKeyboardSource<UnitDisposition>()),
                     tag: &tag, to: colB)
        section.addArrangedSubview(cols)
        containerView.addArrangedSubview(section)

        (section, cols, colA, colB) = newSection()
        var header = newHeader("ReportViewController.patientInformation".localized,
                               subheaderText: "ReportViewController.optional".localized)
        section.addArrangedSubview(header)
        addTextField(source: report, attributeKey: "patient.firstName", tag: &tag, to: colA)
        addTextField(source: report, attributeKey: "patient.lastName", tag: &tag, to: colB)
        addTextField(source: report, attributeKey: "patient.dob", attributeType: .date, tag: &tag, to: colA)
        addTextField(source: report, attributeKey: "patient.ageArray",
                     attributeType: .integerWithUnit(EnumKeyboardSource<PatientAgeUnits>()),
                     tag: &tag, to: colB, withWrapper: true)
        addTextField(source: report, attributeKey: "patient.gender",
                     attributeType: .single(EnumKeyboardSource<PatientGender>()),
                     tag: &tag, to: colA, withWrapper: true)
        section.addArrangedSubview(cols)
        containerView.addArrangedSubview(section)

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

        setEditing(isEditing, animated: false)
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
                     attributeKey: "procedures[\(i)].procedurePerformedAt", attributeType: .datetime, tag: &tag, to: colA)
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
                     attributeKey: "medications[\(i)].medicationAdministeredAt", attributeType: .datetime, tag: &tag, to: colA)
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
        for formField in formFields {
            formField.updateStyle()
        }
        var contentInset = scrollView.contentInset
        contentInset.bottom = commandFooter.frame.height + 16
        scrollView.contentInset = contentInset
    }

    func removeSections(type: AnyClass, greaterThan count: Int) {
        var lastSection: FormSection?
        for view in containerView.arrangedSubviews {
            if let section = view as? FormSection, section.type == type {
                if section.index ?? 0 >= count {
                    let fieldsToRemove = FormSection.fields(in: section)
                    formFields = formFields.filter { !fieldsToRemove.contains($0) }
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
            self.newReport = nil
        }
        for formField in formFields {
            formField.isEditing = editing
            formField.isEnabled = editing
            formField.target = newReport
        }
    }

    func resetFormFields() {
        for formField in formFields {
            if let attributeKey = formField.attributeKey {
                formField.attributeValue = formField.source?.value(forKeyPath: attributeKey) as? NSObject
                if let source = formField.source as? Predictions {
                    formField.status = source.predictionStatus(for: attributeKey)
                }
            }
        }
    }

    func refreshFormFields() {
        for formField in formFields {
            if let attributeKey = formField.attributeKey, let target = formField.target {
                formField.attributeValue = target.value(forKeyPath: attributeKey) as? NSObject
                if let target = formField.target as? Predictions {
                    formField.status = target.predictionStatus(for: attributeKey)
                }
            }
        }
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
        performSegue(withIdentifier: "Record", sender: self)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let vc = segue.destination as? RecordingViewController {
            vc.delegate = self
        }
    }

    // MARK: - FormFieldDelegate

    func formFieldDidChange(_ field: PRKit.FormField) {
        if let attributeKey = field.attributeKey, let target = field.target {
            target.setValue(field.attributeValue, forKeyPath: attributeKey)
        }
    }

    func formField(_ field: PRKit.FormField, wantsToPresent vc: UIViewController) {
        presentAnimated(vc)
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
        if newReport == report {
            newReport?.narrative?.text = processedText
        } else {
            newReport?.narrative?.text = "\(report.narrative?.text ?? "") \(processedText)"
        }
        let formField = formFields.first(where: { $0.target == newReport && $0.attributeKey == "narrative.text" })
        formField?.attributeValue = newReport?.narrative?.text as NSObject?
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            self?.newReport?.extractValues(from: processedText, fileId: fileId, transcriptId: transcriptId,
                                           metadata: metadata, isFinal: isFinal)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.refreshFormFields()
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
