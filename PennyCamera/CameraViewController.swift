//
//  CameraViewController.swift
//  PressedPenny
//
//  Created by Peter Kovacs on 7/25/19.
//  Copyright © 2019 Kovapps. All rights reserved.
//

import UIKit
import Photos
import CoreLocation

class CameraViewController: UIViewController {
    fileprivate var context: CIContext = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
    fileprivate var cameraController: CameraController?
    fileprivate var isCoinMode: Bool = true {
        didSet { setModeButton() }
    }

    @IBOutlet fileprivate weak var captureButton: UIButton!
    @IBOutlet fileprivate weak var capturePreviewView: UIView!
    @IBOutlet fileprivate weak var regionOfInterest: UIView!
    @IBOutlet fileprivate weak var machineRegionOfInterest: UIView!
    @IBOutlet fileprivate weak var imageView: UIImageView!
    @IBOutlet fileprivate weak var coinModeButton: UIButton!
    @IBOutlet fileprivate weak var machineModeButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        cameraController =
            CameraController(isCoinMode: isCoinMode,
                             regionOfInterest: regionOfInterest.frame,
                             frame: view.frame,
                             delegate: self)

        captureButton.layer.borderColor = UIColor.black.cgColor
        captureButton.layer.borderWidth = 2
        captureButton.layer.cornerRadius = min(captureButton.frame.width, captureButton.frame.height) / 2

        regionOfInterest.layer.borderColor = UIColor.white.cgColor
        regionOfInterest.layer.borderWidth = 5
        regionOfInterest.layer.cornerRadius = 8

        machineRegionOfInterest.layer.borderColor = UIColor.white.cgColor
        machineRegionOfInterest.layer.borderWidth = 5
        machineRegionOfInterest.layer.cornerRadius = 8

        cameraController?.prepare { result in
            if case .failure(let error) = result {
                print(error)
            }

            try? self.cameraController?.displayPreview(on: self.capturePreviewView)
        }
    }

    func setModeButton() {
        cameraController?.isCoinMode = isCoinMode
        machineModeButton?.isHidden = isCoinMode
        coinModeButton?.isHidden = !isCoinMode

        regionOfInterest.isHidden = !isCoinMode
        machineRegionOfInterest.isHidden = isCoinMode
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setModeButton()
        cameraController?.start()
        navigationController?.isNavigationBarHidden = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        cameraController?.stop()
        navigationController?.isNavigationBarHidden = false
    }

    @IBAction func buttonTapped(_ sender: Any) {
        if isCoinMode {
            try? cameraController?.captureImage(completion: captureCoin(result:))
        } else {
            try? cameraController?.captureImage(completion: captureMachine(result:))
        }
    }

    func present(image: UIImage) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let controller = storyboard.instantiateViewController(withIdentifier: "ImageView") as! ImageViewController
        controller.image = image
        navigationController?.pushViewController(controller, animated: true)
    }

    func captureMachine(result: Result<UIImage, Error>) {
        switch result {
        case .failure(let error): print(error)
        case .success(let image):
            guard let processed =
                CoinExtractor.captureMachine(on: image.fixedOrientation(),
                                             withROI: machineRegionOfInterest.frame,
                                             withFrame: view.frame) else { return }
            present(image: processed)
        }
    }

    func captureCoin(result: Result<UIImage, Error>) {
        switch( result ) {
        case .failure(let error): print(error)
        case .success(let image):
            guard let processed =
                CoinExtractor.captureEllipse(on: image.fixedOrientation(),
                                             withROI: regionOfInterest.frame,
                                             withFrame: view.frame) else { return }
            present(image: processed)
        }
    }

    @IBAction func toggleMode(_ sender: Any) {
        isCoinMode.toggle()
        self.imageView.image = nil
    }

    override var prefersStatusBarHidden: Bool { true }

    override var shouldAutorotate: Bool { false }
}

extension CameraViewController: CameraDelegate {

    func didProcess(image: UIImage?) {
        self.imageView.image = image
    }
}
