//
//  TransportViewController.swift
//  Triage
//
//  Created by Francis Li on 3/6/24.
//  Copyright © 2024 Francis Li. All rights reserved.
//

import Foundation
import PRKit
import UIKit

struct TransportCart {
    var reports: [Report] = []
    var responder: Responder?
    var facility: Facility?
}

class TransportViewController: UIViewController, TransportReportsViewControllerDelegate, TransportRespondersViewControllerDelegate {
    @IBOutlet weak var segmentedControl: SegmentedControl!
    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var activityIndicatorView: UIActivityIndicatorView!

    var cachedViewControllers: [UIViewController?] = [nil, nil, nil]

    var incident: Incident?
    var cart = TransportCart()

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        tabBarItem.title = "TabBarItem.transport".localized
        tabBarItem.image = UIImage(named: "Transport", in: PRKitBundle.instance, compatibleWith: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if incident == nil, let sceneId = AppSettings.sceneId,
           let scene = AppRealm.open().object(ofType: Scene.self, forPrimaryKey: sceneId) {
            incident = scene.incident.first
        }

        segmentedControl.addSegment(title: "TransportViewController.segment.patients".localized)
        segmentedControl.addSegment(title: "TransportViewController.segment.units".localized)
        segmentedControl.addSegment(title: "TransportViewController.segment.hospitals".localized)

        segmentedControlChanged(segmentedControl)
        activityIndicatorView.stopAnimating()
    }

    func removeCurrentViewController() {
        if children.count > 0 {
            let vc = children[0]
            vc.willMove(toParent: nil)
            vc.view.removeFromSuperview()
            vc.removeFromParent()
        }
    }

    @IBAction func segmentedControlChanged(_ sender: SegmentedControl) {
        removeCurrentViewController()
        var vc = cachedViewControllers[sender.selectedIndex]
        if vc == nil {
            switch sender.selectedIndex {
            case 0:
                vc = UIStoryboard(name: "Scenes", bundle: nil).instantiateViewController(withIdentifier: "TransportReports")
                if let vc = vc as? TransportReportsViewController {
                    vc.delegate = self
                    vc.selectedReports = cart.reports
                    vc.incident = incident
                }
                cachedViewControllers[0] = vc
            case 1:
                vc = UIStoryboard(name: "Scenes", bundle: nil).instantiateViewController(withIdentifier: "TransportResponders")
                if let vc = vc as? TransportRespondersViewController {
                    vc.delegate = self
                    vc.cart = cart
                }
                cachedViewControllers[1] = vc
            default:
                break
            }
        }
        if let vc = vc {
            addChild(vc)
            containerView.addSubview(vc.view)
            vc.view.frame = containerView.bounds
            vc.didMove(toParent: self)
        }
    }

    // MARK: - TransportReportsViewControllerDelegate

    func transportReportsViewController(_ vc: TransportReportsViewController, didSelect report: Report?) {
        if let report = report {
            if let index = cart.reports.firstIndex(of: report) {
                cart.reports.remove(at: index)
            } else {
                cart.reports.append(report)
            }
            vc.selectedReports = cart.reports
        }
    }

    // MARK: - TransportRespondersViewControllerDelegate

    func transportRespondersViewController(_ vc: TransportRespondersViewController, didSelect responder: Responder?) {
        if let responder = responder {
            if cart.responder == responder {
                cart.responder = nil
            } else {
                cart.responder = responder
            }
            vc.cart = cart
        }
    }
}
