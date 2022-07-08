//
//  ReportsViewController.swift
//  Triage
//
//  Created by Francis Li on 1/4/22.
//  Copyright © 2022 Francis Li. All rights reserved.
//

import UIKit
import PRKit
import RealmSwift
import AlignedCollectionViewFlowLayout

class ReportsViewController: UIViewController, CommandHeaderDelegate, CustomTabBarDelegate, PRKit.FormFieldDelegate,
                             UICollectionViewDataSource, UICollectionViewDelegate {
    @IBOutlet weak var commandHeader: CommandHeader!
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var customTabBar: CustomTabBar!

    var incident: Incident?
    var isMCI = false
    var results: Results<Report>?
    var notificationToken: NotificationToken?
    var firstRefresh = true

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem.title = "TabBarItem.patientDetails".localized
        tabBarItem.image = UIImage(named: "Patient", in: PRKitBundle.instance, compatibleWith: nil)
    }

    deinit {
        notificationToken?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if incident == nil, let sceneId = AppSettings.sceneId,
           let scene = AppRealm.open().object(ofType: Scene.self, forPrimaryKey: sceneId) {
            incident = scene.incident.first
            isMCI = scene.isMCI
        }

        let layout = AlignedCollectionViewFlowLayout(horizontalAlignment: .left, verticalAlignment: .top)
        layout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView.setCollectionViewLayout(layout, animated: false)

        if isMCI {
            commandHeader.isSearchHidden = false
            commandHeader.searchField.delegate = self
        } else {
            commandHeader.leftBarButtonItem = UIBarButtonItem(title: "Button.done".localized, style: .plain, target:
                                                                self, action: #selector(dismissAnimated))
        }

        customTabBar.buttonTitle = "Button.addPatient".localized
        customTabBar.delegate = self
        customTabBar.isHidden = true

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        collectionView.register(ReportCollectionViewCell.self, forCellWithReuseIdentifier: "Report")

        performQuery()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !isMCI {
            var contentInset = collectionView.contentInset
            contentInset.bottom = customTabBar.frame.height
            collectionView.contentInset = contentInset
        }
        if traitCollection.horizontalSizeClass == .regular {
            if let layout = collectionView.collectionViewLayout as? AlignedCollectionViewFlowLayout {
                var sectionInset = layout.sectionInset
                let inset = max(0, (collectionView.frame.width - 744) / 2)
                sectionInset.left = inset
                sectionInset.right = inset
                layout.sectionInset = sectionInset
            }
        }
    }

    @objc func performQuery() {
        guard let incident = incident else { return }

        notificationToken?.invalidate()

        let realm = AppRealm.open()
        results = realm.objects(Report.self)
            .filter("incident=%@ AND canonicalId=%@", incident, NSNull())
        if isMCI {
            if let text = commandHeader.searchField.text, !text.isEmpty {
                results = results?.filter("(pin CONTAINS[cd] %@) OR (patient.firstName CONTAINS[cd] %@) OR (patient.lastName CONTAINS[cd] %@)",
                                          text, text, text)
            }
            results = results?.sorted(by: [
                SortDescriptor(keyPath: "filterPriority"),
                SortDescriptor(keyPath: "pin")
            ])
        } else {
            results = results?.sorted(by: [
                SortDescriptor(keyPath: "patient.canonicalId"),
                SortDescriptor(keyPath: "patient.parentId", ascending: false)
            ])
        }
        notificationToken = results?.observe { [weak self] (changes) in
            self?.didObserveRealmChanges(changes)
        }
        refresh()
    }

    @objc func refresh() {
        guard let incident = incident else { return }
        collectionView.refreshControl?.beginRefreshing()
        AppRealm.getReports(incident: incident) { [weak self] (results, error) in
            guard let self = self else { return }
            if let error = error {
                print(error)
            }
            if self.firstRefresh {
                self.firstRefresh = false
                if !self.isMCI {
                    // show add patient button footer
                    self.customTabBar.isHidden = false
                    if let results = results, results.count == 0 {
                        self.presentNewReport(incident: incident, animated: false) { [weak self] in
                            self?.collectionView.refreshControl?.endRefreshing()
                        }
                        return
                    }
                }
            }
            self.collectionView.refreshControl?.endRefreshing()
        }
    }

    func didObserveRealmChanges(_ changes: RealmCollectionChange<Results<Report>>) {
        switch changes {
        case .initial:
            collectionView.reloadData()
        case .update(_, let deletions, let insertions, let modifications):
            collectionView.performBatchUpdates({
                self.collectionView.insertItems(at: insertions.map { IndexPath(row: $0, section: 0) })
                self.collectionView.deleteItems(at: deletions.map { IndexPath(row: $0, section: 0) })
                self.collectionView.reloadItems(at: modifications.map { IndexPath(row: $0, section: 0) })
            }, completion: nil)
        case .error(let error):
            presentAlert(error: error)
        }
    }

    @objc override func newReportCancelled() {
        view.isHidden = true
        dismiss(animated: true) { [weak self] in
            self?.dismiss(animated: false)
        }
    }

    // MARK: - CustomTabBarDelegate

    func customTabBar(_ tabBar: CustomTabBar, didSelect index: Int) {

    }

    func customTabBar(_ tabBar: CustomTabBar, didPress button: UIButton) {
        presentNewReport(incident: incident)
    }

    // MARK: - FormFieldDelegate

    func formFieldDidChange(_ field: PRKit.FormField) {
        performQuery()
    }

    func formFieldShouldReturn(_ field: PRKit.FormField) -> Bool {
        field.resignFirstResponder()
        return false
    }

    // MARK: - ReportContainerViewControllerDelegate

    override func reportContainerViewControllerDidSave(_ vc: ReportContainerViewController) {
        vc.commandHeader.leftBarButtonItem = UIBarButtonItem(title: "NavigationBar.done".localized,
                                                             style: .done,
                                                             target: self,
                                                             action: #selector(self.dismissAnimated))
    }

    // MARK: - UICollectionViewDataSource

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return results?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Report", for: indexPath)
        if let cell = cell as? ReportCollectionViewCell {
            cell.configure(report: results?[indexPath.row], index: indexPath.row)
        }
        return cell
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if let report = results?[indexPath.row] {
            presentReport(report: report, animated: true) {
                collectionView.deselectItem(at: indexPath, animated: false)
            }
        }
    }
}
