//
//  AppDelegate.swift
//  PennyCamera
//
//  Created by Peter Kovacs on 7/25/19.
//  Copyright © 2019 Kovapps. All rights reserved.
//

import UIKit
import Photos


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, CLLocationManagerDelegate {

    var window: UIWindow?
    var photosAuthorization: PHAuthorizationStatus = .notDetermined

    fileprivate func requestPhotoLibraryAuthorization(callback: @escaping () -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        if case .notDetermined = status {
            PHPhotoLibrary.requestAuthorization { (status) in
                self.photosAuthorization = status
                callback()
            }
        } else {
            self.photosAuthorization = status
            callback()
        }
    }

    fileprivate func requestLocationAuthorization() {
        guard CLLocationManager.locationServicesEnabled() else {
            NSLog("Location Services Not Enabled.")
            return
        }

        LocationManager.instance.requestAuthorization()
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        requestPhotoLibraryAuthorization() {
            self.requestLocationAuthorization()
        }

        return true
    }

    // MARK: UISceneSession Lifecycle

    @available(iOS 13.0, *)
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    @available(iOS 13.0, *)
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

