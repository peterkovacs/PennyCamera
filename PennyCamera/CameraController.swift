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
    func didProcess(image: UIImage?)
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
    var depthDataOutput: AVCaptureDepthDataOutput?
    var photoOutput: AVCapturePhotoOutput?
    var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var flashMode: AVCaptureDevice.FlashMode = .off

    var sessionQueue = DispatchQueue(label: "com.kovapps.travel.Camera.Session", attributes: [], autoreleaseFrequency: .workItem)
    var dataOutputQueue = DispatchQueue(label: "com.kovapps.travel.Camera.Output", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)

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
        sessionQueue.async {
            do {
                try self.configureSession()

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
        if let photoOutput = self.photoOutput, photoOutput.isDepthDataDeliveryEnabled {
            settings.isDepthDataDeliveryEnabled = true
            settings.isDepthDataFiltered = true
        }

        self.photoOutput?.capturePhoto(with: settings, delegate: self)
        self.photoCaptureCompletionBlock = completion
    }


    // MARK: Configure Capture Session

    private func configureSession() throws {
        self.captureSession = AVCaptureSession()

        self.rearCamera = try self.configureCaptureDevice()
        try self.configureDeviceInputs()
        try self.configureOutputs()
    }

    private func configureCaptureDeviceForDepth() throws -> AVCaptureDevice {
        guard let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) else { throw CameraControllerError.noCamerasAvailable }

        let availableFormats = device.formats.filter {
            !$0.supportedDepthDataFormats.isEmpty && $0.mediaType == AVMediaType.video
        }.filter {
            let dimensions = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
            return max( dimensions.width, dimensions.height ) >= 1280
        }
        print("Available Formats", availableFormats)
        print("Depth Data Formats", availableFormats[0].supportedDepthDataFormats)

        try device.lockForConfiguration()
        device.focusMode = .continuousAutoFocus
        device.activeFormat = availableFormats[0]
        device.activeDepthDataFormat = availableFormats[0].supportedDepthDataFormats.first
        device.unlockForConfiguration()

        return device
    }

    private func configureCaptureDevice() throws -> AVCaptureDevice {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CameraControllerError.noCamerasAvailable }

        try device.lockForConfiguration()
        device.focusMode = .continuousAutoFocus
        device.unlockForConfiguration()

        return device
    }

    private func configureDeviceInputs() throws {
        guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }

        if let rearCamera = self.rearCamera {
            let rearCameraInput = try AVCaptureDeviceInput(device: rearCamera)

            guard captureSession.canAddInput(rearCameraInput) else { throw CameraControllerError.inputsAreInvalid }
            captureSession.addInput(rearCameraInput)

            self.rearCameraInput = rearCameraInput
        }
        else { throw CameraControllerError.noCamerasAvailable }
    }

    private func configureOutputs() throws {
        guard let captureSession = self.captureSession else { throw CameraControllerError.captureSessionIsMissing }
        var depthEnabled = false

        captureSession.beginConfiguration()

        let photoOutput = AVCapturePhotoOutput()
        photoOutput.setPreparedPhotoSettingsArray(
            [AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])],
            completionHandler: nil
        )
        photoOutput.isHighResolutionCaptureEnabled = true
        photoOutput.isLivePhotoCaptureEnabled = false

        // Capture Depth information for "Machine" pictures.
        if photoOutput.isDepthDataDeliverySupported {
            photoOutput.isDepthDataDeliveryEnabled = true
            depthEnabled = true
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        self.photoOutput = photoOutput

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [ kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA) ]
        videoOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)

            if let connection = videoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
            }
        }
        self.videoOutput = videoOutput

        if depthEnabled {
            let depthDataOutput = AVCaptureDepthDataOutput()
            depthDataOutput.setDelegate(self, callbackQueue: dataOutputQueue)
            depthDataOutput.alwaysDiscardsLateDepthData = true
            depthDataOutput.isFilteringEnabled = true // i.e. smooth.

            if captureSession.canAddOutput(depthDataOutput) {
                captureSession.addOutput(depthDataOutput)

                if let connection = depthDataOutput.connection(with: .depthData) {
                    connection.videoOrientation = .portrait
                    connection.isEnabled = true
                }

                // Use an AVCaptureDataOutputSynchronizer to synchronize the video data and depth data outputs.
                // The first output in the dataOutputs array, in this case the AVCaptureVideoDataOutput, is the "master" output.
                let outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthDataOutput])
                outputSynchronizer.setDelegate(self, queue: dataOutputQueue)
                self.outputSynchronizer = outputSynchronizer
            }
            self.depthDataOutput = depthDataOutput
        }

        captureSession.commitConfiguration()

        try self.rearCamera?.lockForConfiguration()

        if let device = self.rearCamera {
            device.focusMode = .continuousAutoFocus
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)

            if depthEnabled {
                let availableFormats = device.formats.filter {
                    !$0.supportedDepthDataFormats.isEmpty && $0.mediaType == AVMediaType.video
                }
                device.activeFormat = availableFormats[0]
                device.activeDepthDataFormat = availableFormats[0].supportedDepthDataFormats.first
            }
        }

        captureSession.startRunning()

        rearCamera?.unlockForConfiguration()
    }

    func process(video sampleBuffer: CMSampleBuffer) {
        guard isCoinMode else { return }
        guard let buffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let image = CoinExtractor.drawEllipse(on: buffer, withROI: regionOfInterest, withFrame: frame)

        DispatchQueue.main.async {
            self.delegate?.didProcess(image: image)
        }
    }

    func process(depth depthData: AVDepthData) {
        guard !isCoinMode else { return }

        let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        print("Processing depthData", converted.depthDataMap, CVPixelBufferGetWidth(converted.depthDataMap), CVPixelBufferGetHeight(converted.depthDataMap))

    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        process(video: sampleBuffer)
    }
}

extension CameraController: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        process(depth: depthData)
    }
}

extension CameraController: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        if let videoOutput = self.videoOutput, let video = synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData, !video.sampleBufferWasDropped {
            process(video: video.sampleBuffer)
        }

        if let depthDataOutput = self.depthDataOutput, let depth = synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData, !depth.depthDataWasDropped {
            process(depth: depth.depthData)
        }
    }
}

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

        photoCaptureCompletionBlock?(.success(image))
    }
}
