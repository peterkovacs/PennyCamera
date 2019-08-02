//
//  CameraController.swift
//  PressedPenny
//
//  Created by Peter Kovacs on 7/25/19.
//  Copyright © 2019 Kovapps. All rights reserved.
//

import AVFoundation
import UIKit

protocol CameraDelegate {
    func didProcess(image: UIImage)
}

class CameraController: NSObject {
    var isCoinMode: Bool
    var regionOfInterest: CGRect
    var frame: CGRect
    var context: CIContext = CIContext(options: [.useSoftwareRenderer: false])
    var delegate: CameraDelegate?

    var captureSession: AVCaptureSession?
    var rearCamera: AVCaptureDevice?
    var rearCameraInput: AVCaptureDeviceInput?
    var videoOutput: AVCaptureVideoDataOutput?
    var photoOutput: AVCapturePhotoOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var flashMode: AVCaptureDevice.FlashMode = .off

    fileprivate var photoCaptureCompletionBlock: ((Result<UIImage, Error>) -> Void)?

    enum CameraControllerError: Error {
        case captureSessionAlreadyRunning
        case captureSessionIsMissing
        case inputsAreInvalid
        case invalidOperation
        case noCamerasAvailable
        case unknown
    }

    init(isCoinMode: Bool, regionOfInterest: CGRect, frame: CGRect, delegate: CameraDelegate?) {
        self.isCoinMode = isCoinMode
        self.regionOfInterest = regionOfInterest
        self.frame = frame
        self.delegate = delegate
    }

    func prepare(completionHandler: @escaping (Result<Void, Error>) -> ()) {
        DispatchQueue(label: "com.kovapps.travel.Camera.prepare").async {
            do {
                self.createCaptureSession()
                try self.configureCaptureDevices()
                try self.configureDeviceInputs()
                try self.configurePhotoOutput()

                DispatchQueue.main.async {
                    completionHandler(.success(()))
                }
            }
            catch {
                DispatchQueue.main.async {
                    completionHandler(.failure(error))
                }
            }
        }
    }

    func start() {
        guard let captureSession = self.captureSession, !captureSession.isRunning else { return }

        captureSession.startRunning()
    }

    func stop() {
        guard let captureSession = self.captureSession, captureSession.isRunning else { return }

        captureSession.stopRunning()
    }

    func displayPreview(on view: UIView) throws {
        guard let captureSession = self.captureSession, captureSession.isRunning else { throw CameraControllerError.captureSessionIsMissing }

        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer?.videoGravity = .resizeAspectFill
        self.previewLayer?.connection?.videoOrientation = .portrait

        view.layer.insertSublayer(self.previewLayer!, at: 0)
        self.previewLayer?.frame = view.frame
    }

    func captureImage(completion: @escaping (Result<UIImage, Error>) -> Void) throws {
        guard let captureSession = captureSession, captureSession.isRunning else { throw CameraControllerError.captureSessionIsMissing }

        let settings = AVCapturePhotoSettings()
        settings.flashMode = self.flashMode

        self.photoOutput?.capturePhoto(with: settings, delegate: self)
        self.photoCaptureCompletionBlock = completion
    }

    private func createCaptureSession() {
        self.captureSession = AVCaptureSession()
//        self.captureSession?.sessionPreset = .high
    }

    private func configureCaptureDevices() throws {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified)
        guard !session.devices.isEmpty else { throw CameraControllerError.noCamerasAvailable }

        for camera in session.devices {
            if camera.position == .back {
                self.rearCamera = camera

                try camera.lockForConfiguration()
                camera.focusMode = .continuousAutoFocus
                camera.unlockForConfiguration()
            }
        }
    }

    private func configureDeviceInputs() throws {
        guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }

        if let rearCamera = self.rearCamera {
            let rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)

            if captureSession.canAddInput(rearCameraInput) {
                captureSession.addInput(rearCameraInput)
            }

            self.rearCameraInput = rearCameraInput
        }
        else { throw CameraControllerError.noCamerasAvailable }
    }

    private func configurePhotoOutput() throws {
        guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }

        captureSession.beginConfiguration()
        let photoOutput = AVCapturePhotoOutput()
        photoOutput.setPreparedPhotoSettingsArray(
            [AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])],
            completionHandler: nil
        )
        photoOutput.isHighResolutionCaptureEnabled = true
        photoOutput.isLivePhotoCaptureEnabled = false
        photoOutput.isDepthDataDeliveryEnabled = photoOutput.isDepthDataDeliverySupported

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        self.photoOutput = photoOutput

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [ kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA) ]

        let queue = DispatchQueue(label: "com.kovapps.travel.Camera.VideoCapture")
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        self.videoOutput = videoOutput

//        let depthOutput = AVCaptureDepthDataOutput()
//        depthOutput.setDelegate(self, callbackQueue: queue)
//        depthOutput.alwaysDiscardsLateDepthData = true
//
//        if captureSession.canAddOutput(depthOutput) {
//            captureSession.addOutput(depthOutput)
//        } else {
//            print("COULD NOT ADD AVCaptureDepthDataOutput()")
//        }

        captureSession.commitConfiguration()

        try self.rearCamera?.lockForConfiguration()
        self.rearCamera?.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
        self.rearCamera?.unlockForConfiguration()

        captureSession.startRunning()
    }

    func machineFilter(_ input: CIImage, radius: CGFloat ) -> CIImage? {
        let region = CoinExtractor.calculateScaledROI(regionOfInterest, frame: frame, extent: input.extent.size)

        print("ROI", regionOfInterest, frame, input.extent.size, region)

        let overlay = CIImage(color: CIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.5))
        let overlay2 = CIImage(color: CIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 0.5))
            .cropped(to: region.insetBy(dx: -10.0, dy: 10.0))
//            .transformed(by: CGAffineTransform(translationX: region.origin.x, y: region.origin.y))

        return overlay2.composited(over: overlay.composited(over: input).cropped(to: region))

        guard let maskedFilter = CIFilter(name: "CIMaskedVariableBlur") else { return nil }
        maskedFilter.setValue(input, forKey: kCIInputImageKey)
        maskedFilter.setValue(radius, forKey: kCIInputRadiusKey)
        maskedFilter.setValue(overlay, forKey: "inputMask")

        return maskedFilter.outputImage//?.cropped(to: region)

    }

}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        let image = CIImage(cvImageBuffer: buffer).oriented(.right)
        let resultImage = isCoinMode ?
            CoinExtractor.drawEllipse(on: image, with: context, withROI: regionOfInterest, withFrame: frame) :
            machineFilter(image, radius: 10).map { UIImage(ciImage: $0) }
        CVPixelBufferUnlockBaseAddress(buffer, .readOnly)

        if let resultImage = resultImage {
            DispatchQueue.main.async {
                self.delegate?.didProcess(image: resultImage)
            }
        }
    }
}

//extension CameraController: AVCaptureDepthDataOutputDelegate {
//    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
//
//    }
//}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            photoCaptureCompletionBlock?(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            photoCaptureCompletionBlock?(.failure(CameraControllerError.unknown))
            return
        }

        guard let image = UIImage(data: data) else {
            photoCaptureCompletionBlock?(.failure(CameraControllerError.inputsAreInvalid))
            return
        }

        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

        photoCaptureCompletionBlock?(.success(image))
    }
}
