//
//  LocationManager.swift
//  PennyCamera
//
//  Created by Peter Kovacs on 7/31/19.
//  Copyright © 2019 Kovapps. All rights reserved.
//

import Foundation
import CoreLocation

class LocationManager: NSObject, CLLocationManagerDelegate {
    private var authorization: CLAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()
    public var location: CLLocation? = nil

    private override init() {
        super.init()
        authorization = CLLocationManager.authorizationStatus()
        manager.delegate = self
    }

    func authorized(_ status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse {
            manager.distanceFilter = kCLDistanceFilterNone
            manager.startUpdatingLocation()
        } else {
            print("Location Authorization", status)
        }
    }

    func requestAuthorization() {
        guard authorization == .notDetermined else {
            authorized(authorization)
            return
        }

        manager.requestWhenInUseAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        self.authorization = status
        authorized(status)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

//        NSLog("Location Updated %@", location.description)
        self.location = location
    }

    static var instance: LocationManager = LocationManager()
}
