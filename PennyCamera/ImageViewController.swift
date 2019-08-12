//
//  ImageViewController.swift
//  PennyCamera
//
//  Created by Peter Kovacs on 7/28/19.
//  Copyright © 2019 Kovapps. All rights reserved.
//

import UIKit
import Photos
import ImageIO
import CoreServices

class ImageViewController: UIViewController {
    var image: UIImage!
    @IBOutlet weak var imageView: UIImageView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        imageView.image = image

        switch (UIApplication.shared.delegate as! AppDelegate).photosAuthorization {
        case .notDetermined, .authorized:
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(save))
        default:
            break
        }

    }

    @objc func save() {
        print("Saving Coin")
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
        let location = LocationManager.instance.location
        guard image.save(jpeg: url, with: location) else { return }

        do {
            try PHPhotoLibrary.shared().performChangesAndWait {
                let asset = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                asset?.location = location
            }

            navigationController?.popViewController(animated: true)
        } catch {
            let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

}
