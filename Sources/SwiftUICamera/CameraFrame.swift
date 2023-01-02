//Created by: Sean Li

import Foundation
import AVFoundation
import Combine

public final class CameraFrame: NSObject, ObservableObject {
  public typealias SharedBuffer = AnyPublisher<CVPixelBuffer?, Never>
  @Published private(set) var current: CVPixelBuffer?
  public private(set) var sharedBuffer: SharedBuffer?
  public static let shared = CameraFrame()
  private let camera = Camera.shared
  
  let videoOutputQueue = DispatchQueue(
    label: "org.madpro.chirping.frame.outputq",
    qos: .userInitiated,
    attributes: [],
    autoreleaseFrequency: .workItem)
  
  private override init() {
    super.init()
    self.sharedBuffer = $current
      .share()
      .eraseToAnyPublisher()
    Camera.shared.set(self, queue: videoOutputQueue)
  }
}

extension CameraFrame: AVCaptureVideoDataOutputSampleBufferDelegate {
  public func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    if let buffer = sampleBuffer.imageBuffer {
      DispatchQueue.main.async {
        self.current = buffer
      }
    }
  }
}
