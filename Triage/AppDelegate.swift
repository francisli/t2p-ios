//
//  AppDelegate.swift
//  Triage
//
//  Created by Francis Li on 11/1/19.
//  Copyright © 2019 Francis Li. All rights reserved.
//

import GoogleMaps
import Keys
import RollbarNotifier
import RollbarPLCrashReporter
import UIKit
import ICD10Kit
import RxNormKit

@UIApplicationMain

class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    static func enterScene(id: String) {
        AppSettings.sceneId = id
        let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "ActiveScene")
        for window in UIApplication.shared.windows where window.isKeyWindow {
            window.rootViewController = vc
            break
        }
    }

    static func leaveScene() -> UIViewController {
        AppSettings.sceneId = nil
        let vc = UIStoryboard(name: "Incidents", bundle: nil).instantiateInitialViewController()!
//        let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "NoActiveScene")
        for window in UIApplication.shared.windows where window.isKeyWindow {
            window.rootViewController = vc
            break
        }
        return vc
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let keys = TriageKeys()

        let rollbarConfig = RollbarConfig()
        rollbarConfig.destination.accessToken = keys.rollbarPostClientItemAccessToken
        rollbarConfig.destination.environment = keys.rollbarEnvironment
        rollbarConfig.developerOptions.suppressSdkInfoLogging = true
        let rollbarCrashCollector = RollbarPLCrashCollector()
        Rollbar.initWithConfiguration(rollbarConfig, crashCollector: rollbarCrashCollector)

        GMSServices.provideAPIKey(keys.googleMapsSdkApiKey)

        CMRealm.configure(url: Bundle.main.url(forResource: "ICD10CM", withExtension: "realm"), isReadOnly: true)
        RxNRealm.configure(url: Bundle.main.url(forResource: "RxNorm", withExtension: "realm"), isReadOnly: true)

        UIBarButtonItem.appearance().setTitleTextAttributes([
            .font: UIFont.copySBold,
            .foregroundColor: UIColor.mainGrey
        ], for: .normal)
        UIBarButtonItem.appearance().setTitleTextAttributes([
            .font: UIFont.copySBold,
            .foregroundColor: UIColor.mainGrey
        ], for: .highlighted)
        UIBarButtonItem.appearance().setTitleTextAttributes([
            .font: UIFont.copySBold,
            .foregroundColor: UIColor.lowPriorityGrey
        ], for: .disabled)

        UILabel.appearance(whenContainedInInstancesOf: [UISegmentedControl.self]).numberOfLines = 0

        UINavigationBar.appearance().barTintColor = .white
        UINavigationBar.appearance().tintColor = .mainGrey

        UITabBar.appearance().barTintColor = .white

        UIToolbar.appearance().backgroundColor = .bgBackground

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state.
        // This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or
        // when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks.
        // Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to
        // restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate:
        // when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state;
        // here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive.
        // If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }

}
