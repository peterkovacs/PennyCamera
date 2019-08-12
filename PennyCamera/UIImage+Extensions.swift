//
//  UIImage+Orientation.swift
//  PennyCamera
//
//  Created by Peter Kovacs on 7/28/19.
//  Copyright © 2019 Kovapps. All rights reserved.
//

import Foundation
import UIKit
import CoreLocation
import CoreServices

extension CLLocation {

    var metadata: NSMutableDictionary {
        let gpsMetadata = NSMutableDictionary()
        let altitudeRef = altitude < 0.0 ? 1 : 0
        let latitudeRef = coordinate.latitude < 0.0 ? "S" : "N"
        let longitudeRef = coordinate.longitude < 0.0 ? "W" : "E"

        gpsMetadata[ kCGImagePropertyGPSLatitude as String ] = abs(self.coordinate.latitude)
        gpsMetadata[ kCGImagePropertyGPSLongitude as String ] = abs(self.coordinate.longitude)
        gpsMetadata[ kCGImagePropertyGPSLatitudeRef as String ] = latitudeRef
        gpsMetadata[ kCGImagePropertyGPSLongitudeRef as String ] = longitudeRef
        gpsMetadata[ kCGImagePropertyGPSAltitude as String ] = Int(abs(altitude))
        gpsMetadata[ kCGImagePropertyGPSAltitudeRef as String ] = altitudeRef

        let timeFormatter = DateFormatter()
        timeFormatter.timeZone = TimeZone(abbreviation: "UTC")
        timeFormatter.dateFormat = "HH:mm:ss.SSSSSS"
        gpsMetadata[ kCGImagePropertyGPSTimeStamp as String ] = timeFormatter.string(from: timestamp)

        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        dateFormatter.dateFormat = "yyyy:MM:dd"

        gpsMetadata[ kCGImagePropertyGPSDateStamp as String ] = dateFormatter.string(from: timestamp)
        gpsMetadata[ kCGImagePropertyGPSVersion as String ] = "2.2.0.0"

        return gpsMetadata
    }
}

extension UIImage {
    func save(png url: URL, with location: CLLocation?) -> Bool {
        guard let data = pngData() else { return false }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else { return false }

        let metadata = location?.metadata
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary?)

        return CGImageDestinationFinalize(destination)
    }

    func save(jpeg url: URL, with location: CLLocation?) -> Bool {
        guard let data = jpegData(compressionQuality: 0.9) else { return false }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeJPEG, 1, nil) else { return false }

        let metadata = location?.metadata
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary?)

        return CGImageDestinationFinalize(destination)
    }

    func fixedOrientation() -> UIImage {
        guard let cgImage = self.cgImage else { return self }
        if imageOrientation == .up { return self }
        var transform: CGAffineTransform = .identity

        switch imageOrientation {
        case .up, .upMirrored:
            break
        case .down, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: size.height)
            transform = transform.rotated(by: CGFloat.pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.rotated(by: CGFloat.pi / 2)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: size.height)
            transform = transform.rotated(by: -CGFloat.pi / 2)
        @unknown default:
            break
        }

        switch imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        default:
            break
        }

        let context = CGContext(data: nil,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: cgImage.bitsPerComponent,
                                bytesPerRow: 0,
                                space: cgImage.colorSpace!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

        context.concatenate(transform)

        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.height, height: size.width))
        default:
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }

        return UIImage(cgImage: context.makeImage()!)
    }
}

