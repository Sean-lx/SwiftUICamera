//Created by: Sean Li

import Foundation
import AVFoundation

//MARK: - Camera Error Enum
public enum CameraError: Error {
  case cameraUnavailable
  case cannotAddInput
  case cannotAddOutput
  case createCaptureInput(Error)
  case deniedAuthorization
  case restrictedAuthorization
  case unknownAuthorization
}

extension CameraError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .cameraUnavailable:
      return "Camera unavailable"
    case .cannotAddInput:
      return "Cannot add capture input to session"
    case .cannotAddOutput:
      return "Cannot add video output to session"
    case .createCaptureInput(let error):
      return "Creating capture input for camera: \(error.localizedDescription)"
    case .deniedAuthorization:
      return "Camera access denied"
    case .restrictedAuthorization:
      return "Attempting to access a restricted capture device"
    case .unknownAuthorization:
      return "Unknown authorization status for capture device"
    }
  }
}

public final class Camera: ObservableObject {
  //MARK: - Status Enum
  // An internal enumeration to represent the status of the camera.
  public enum Status {
    case unconfigured
    case configured
    case unauthorized
    case failed
  }
  
  //MARK: - Properties and Publishers
  public static let shared = Camera()
  
  /// An error to represent any camera-related error.
  /// We made it a published property so that other objects can
  /// subscribe to this stream and handle any errors as necessary.
  @Published public var error: CameraError?
  
  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "org.madpro.chirping.camera.sessionq")
  private var currentSessionInput: AVCaptureInput?
  private let currentSessionOutput = AVCaptureVideoDataOutput()
  
  // The current status of the camera
  private var status = Status.unconfigured
  
  //MARK: - Init
  private init() {
    configure()
  }
  
  private func configure() {
    checkPermissions()
    sessionQueue.async {
      self.configureCaptureSession()
    }
  }
  
  private func set(error: CameraError?) {
    DispatchQueue.main.async {
      self.error = error
    }
  }
  
  //MARK: - Power on/off
  public func open() {
    session.startRunning()
  }
  
  public func close() {
    session.stopRunning()
  }
  
  //MARK: - Session Quality
  public func setCameraQuality(_ quality: AVCaptureSession.Preset = .high) {
    session.beginConfiguration()
    defer {
      session.commitConfiguration()
    }
    if session.canSetSessionPreset(quality) {
      session.sessionPreset = quality
    }
  }
  
  //MARK: - Set Camera Position
  public func setCameraPosition(_ position: AVCaptureDevice.Position) {
    guard status == .configured else {
      configure()
      return
    }
    guard let currentInput = currentSessionInput else {
      return
    }
    
    close()
    session.removeInput(currentInput)
    session.removeOutput(currentSessionOutput)
    guard configureCaptureSessionInput(position) else {
      status = .unconfigured
      configure()
      return
    }
    guard configureCaptureSessionOutput() else {
      status = .unconfigured
      configure()
      return
    }
    open()
  }
  
  //MARK: - Set Delegate
  // Set the delegate that receives the camera data.
  public func set(
    _ delegate: AVCaptureVideoDataOutputSampleBufferDelegate,
    queue: DispatchQueue
  ) {
    sessionQueue.async {
      self.currentSessionOutput.setSampleBufferDelegate(delegate, queue: queue)
    }
  }
  
  //MARK: - Chcke User Permissions
  /// For any app that needs to request camera access, we need to include
  /// a usage string in Info.plist.
  /// We can find under the key Privacy – Camera Usage Description
  /// or the raw key NSCameraUsageDescription.
  /// If we don’t set this key, then the app will crash as soon as
  /// our code tries to access the camera.
  private func checkPermissions() {
    // We switch on the camera’s authorization status, specifically for video.
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .notDetermined:
      /// If the returned device status is undetermined,
      /// we suspend the session queue and have iOS request permission
      /// to use the camera.
      sessionQueue.suspend()
      AVCaptureDevice.requestAccess(for: .video) { authorized in
        /// If the user denies access, then we set the CameraManager‘s status
        /// to .unauthorized and set the error. Regardless of the outcome,
        /// we resume the session queue.
        if !authorized {
          self.status = .unauthorized
          self.set(error: .deniedAuthorization)
        }
        self.sessionQueue.resume()
      }
      /// For the .restricted and .denied statuses, we set the CameraManager‘s
      /// status to .unauthorized and set an appropriate error.
    case .restricted:
      status = .unauthorized
      set(error: .restrictedAuthorization)
    case .denied:
      status = .unauthorized
      set(error: .deniedAuthorization)
      /// In the case that permission was already given, nothing needs to be done,
      /// so we break out of the switch.
    case .authorized:
      break
      /// We add an unknown default case — just in case
      /// Apple adds more cases to AVAuthorizationStatus in the future.
    @unknown default:
      status = .unauthorized
      set(error: .unknownAuthorization)
    }
  }
  
  //MARK: - Configure AVCaptureSession
  /// Whenever you want to capture some sort of media — whether
  /// it’s audio, video or depth data — AVCaptureSession is what you want.
  /// The main pieces to setting up a capture session are:
  /// - AVCaptureDevice: a representation of the hardware device to use.
  /// - AVCaptureDeviceInput: provides a bridge from the device to the AVCaptureSession.
  /// - AVCaptureSession: manages the flow of data between capture inputs and outputs.
  ///                     It can connect one or more inputs to one or more outputs.
  /// - AVCaptureOutput: an abstract class representing objects that output the captured media.
  ///                    We’ll use AVCaptureVideoDataOutput, which is a concrete implementation
  ///                    of this class.
  /// When there are so many potential points of failure,
  /// having good error management will help you debug any problems much more quickly!
  /// Plus, it’s a significantly better user experience.
  private func configureCaptureSession() {
    guard status == .unconfigured else {
      return
    }
    
    guard configureCaptureSessionInput() else {
      return
    }
    guard configureCaptureSessionOutput() else {
      return
    }
    
    status = .configured
  }
  
  //MARK: - Camera Device
  private func getCameraDevice(_ position: AVCaptureDevice.Position = .back)
  -> AVCaptureDevice?
  {
    let deviceTypes: [AVCaptureDevice.DeviceType] =
    [.builtInTrueDepthCamera, .builtInDualCamera, .builtInWideAngleCamera]
    let discoverySession =
    AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes,
                                     mediaType: .video,
                                     position: .unspecified)
    let devices = discoverySession.devices
    guard !devices.isEmpty else {
      return nil
    }
    
    guard
      let device = devices.first(where: { device in device.position == position })
    else {
      return devices.first
    }
    
    return device
  }
  
  //MARK: - Input
  private func configureCaptureSessionInput(_ position: AVCaptureDevice.Position = .back)
  -> Bool
  {
    guard let camera = getCameraDevice(position) else {
      set(error: .cameraUnavailable)
      status = .failed
      return false
    }
    
    session.beginConfiguration()
    defer {
      session.commitConfiguration()
    }
    
    do {
      /// Try to create an AVCaptureDeviceInput based on the camera.
      /// Since this call can throw, we wrap the code in a do-catch block.
      let cameraInput = try AVCaptureDeviceInput(device: camera)
      currentSessionInput = cameraInput
      /// Add the camera input to AVCaptureSession, if possible.
      /// It’s always a good idea to check if it can be added before adding it.
      guard session.canAddInput(cameraInput) else {
        set(error: .cannotAddInput)
        status = .failed
        return false
      }
      session.addInput(cameraInput)
    } catch {
      set(error: .createCaptureInput(error))
      status = .failed
      return false
    }
    
    return true
  }
  
  //MARK: - Output
  private func configureCaptureSessionOutput() -> Bool {
    /// Check to see if we can add AVCaptureVideoDataOutput
    /// to the session before adding it.
    /// This pattern is similar to when we added the input.
    guard session.canAddOutput(currentSessionOutput) else {
      set(error: .cannotAddOutput)
      status = .failed
      return false
    }
    
    session.beginConfiguration()
    defer {
      session.commitConfiguration()
    }
    
    session.addOutput(currentSessionOutput)
    currentSessionOutput.videoSettings =
    [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    currentSessionOutput.alwaysDiscardsLateVideoFrames = true
    let videoConnection = currentSessionOutput.connection(with: .video)
    videoConnection?.videoOrientation = .portrait
    return true
  }
}
