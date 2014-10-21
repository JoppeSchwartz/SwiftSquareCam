//
//  ViewController.swift
//  SwiftSquareCam
//
//  Created by Joseph Schwartz on 9/23/14.
//  Copyright (c) 2014 Joseph Schwartz. All rights reserved.
//

import UIKit
import AVFoundation
import CoreImage
import ImageIO
import AssetsLibrary


let kCapturingStillImageProp = "capturingStillImage"
let kOutputDataQueueName = "VideoDataOutputQueue"
var kIsCapturingStillImageContext = UInt8()//"IsCapturingStillImageContext"
let kFaceLayerName = "FaceLayer"


class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private var _videoSession: AVCaptureSession! = AVCaptureSession()
    private var _cameraDevice: AVCaptureDevice!
    private var _imageOutput:AVCaptureStillImageOutput = AVCaptureStillImageOutput()
    private var _videoDataOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
    private var _videoDataOutputQueue:dispatch_queue_t!
    private var _avConnection: AVCaptureConnection!
    private var _faceDetector: CIDetector!
    private var _effectiveScale: Float = 1.0
    private var _previewLayer: AVCaptureVideoPreviewLayer!
    private let _squareImage = UIImage(named: "squarePNG")
    private var _flashView: UIView!
    private var _detectFaces = false
    private var _isUsingFrontFacingCamera = false
    
    
    @IBOutlet weak var previewView: UIView!
    
//    @IBOutlet weak var statusLabel: UILabel!

    func setupAVSession() {
        
        _videoSession.sessionPreset = AVCaptureSessionPreset640x480
        _cameraDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        if (_cameraDevice == nil) {
            fatalError("Error: Failed to obtain interface to camera.")
        }
        var errPtr: NSError?
        if _cameraDevice.lockForConfiguration(&errPtr) {
            if _cameraDevice.lowLightBoostSupported {
                _cameraDevice.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
            _cameraDevice.unlockForConfiguration()
        } else {
            println("Could not lock camera for configuration.")
        }
        var err: NSErrorPointer = nil
        var deviceInput: AVCaptureDeviceInput = AVCaptureDeviceInput.deviceInputWithDevice(_cameraDevice, error:err) as AVCaptureDeviceInput
        assert (err==nil)
        if _videoSession.canAddInput(deviceInput) {
            _videoSession.addInput(deviceInput)
        }
        else {
            takedownVideoSession()
            fatalError("Video session can't add camera input.")
        }
        
        //println("Output settings: \(_imageOutput.outputSettings)")
        _imageOutput.addObserver(self, forKeyPath: kCapturingStillImageProp, options: .New, context: &kIsCapturingStillImageContext)
        
        if _videoSession.canAddOutput(_imageOutput) {
            _videoSession.addOutput(_imageOutput)
        }
        else {
            takedownVideoSession()
            fatalError("Video session can't add image output.")
        }
        
        // we want BGRA, both CoreGraphics and OpenGL work well with 'BGRA'
        var rgbOutputSettings: [NSObject:AnyObject] = [kCVPixelBufferPixelFormatTypeKey: kCMPixelFormat_32BGRA]
        _videoDataOutput.videoSettings = rgbOutputSettings
        // discard if the data output queue is blocked (as we process the still image)
        _videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        // create a serial dispatch queue used for the sample buffer delegate as well as when a still image is captured
        // a serial dispatch queue must be used to guarantee that video frames will be delivered in order
        // see the header doc for setSampleBufferDelegate:queue: for more information
        _videoDataOutputQueue = dispatch_queue_create(kOutputDataQueueName, DISPATCH_QUEUE_SERIAL)
        _videoDataOutput.setSampleBufferDelegate(self, queue: _videoDataOutputQueue)
        
        
        //  Add this output to the session
        if (_videoSession.canAddOutput(_videoDataOutput)) {
            _videoSession.addOutput(_videoDataOutput)
        }
        else {
            takedownVideoSession()
            fatalError("Video session can't add video data output.")
        }
        
        //  Disable this output for now.
        _videoDataOutput.connectionWithMediaType(AVMediaTypeVideo).enabled = false
        
        //  Set up the preview layer, except for layout which can't be done yet.
        _previewLayer = AVCaptureVideoPreviewLayer(session:_videoSession)
        _previewLayer.backgroundColor = UIColor.blackColor().CGColor
        _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
        
        //_avConnection = _videoDataOutput.connectionWithMediaType(AVMediaTypeVideo)
        _avConnection = _previewLayer.connection
        
        //  Start the video session
        _videoSession.startRunning()

    }
    
  
    func takedownVideoSession() {
//        if _videoDataOutputQueue != nil {
//            dispatch_release(_videoDataOutputQueue)
//        }
        _imageOutput.removeObserver(self, forKeyPath: kCapturingStillImageProp)
        if _videoSession != nil {
            _videoSession.stopRunning()
        }
        _previewLayer.removeFromSuperlayer()
    }
    
    deinit
    {
        takedownVideoSession()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        //  Set up the video session and face detector.
        self.setupAVSession()

    }
    
    //  Need to finish setting up the preview layer here because that's when the layout is responsive.
    override func viewWillAppear(animated: Bool) {
        
        self.view.layoutIfNeeded()
        let rootLayer = previewView.layer
        rootLayer.masksToBounds = true
        let bounds = rootLayer.bounds
        _previewLayer.frame = bounds
        rootLayer.addSublayer(_previewLayer)

    }

    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
  

    //  Performs a flash bulb animation when taking a picture.
    override func observeValueForKeyPath(keyPath:String, ofObject:AnyObject, change:[NSObject:AnyObject], context:UnsafeMutablePointer<Void>) {

        if context == &kIsCapturingStillImageContext {
            if let isCapturing = change[NSKeyValueChangeNewKey]?.boolValue  {

                if isCapturing {
                    _flashView = UIView(frame:previewView.frame)
                // do flash bulb like animation
                    _flashView.backgroundColor = UIColor.whiteColor()
                    _flashView.alpha = 0.0
                    self.view.window?.addSubview(_flashView)
                    UIView.animateWithDuration(0.2, animations: { () -> Void in
                        self._flashView.alpha = 1.0
                    })
                }
                else {
                    UIView.animateWithDuration(0.2, animations: { () -> Void in
                        self._flashView.alpha = 0.0
                    }, completion: { (Bool finished)-> Void in
                        self._flashView.removeFromSuperview()
                        self._flashView = nil
                    })
                }
            }
        }
        else {
            super.observeValueForKeyPath(keyPath, ofObject: ofObject, change: change, context: context)
        }
    }

    // utility routine to display error aleart if takePicture fails
    func displayErrorOnMainQueue( error:NSError, message: String) {
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            let alertController = UIAlertController(
                title: "\(message) \(error.code)",
                message: error.localizedDescription,
                preferredStyle: UIAlertControllerStyle.Alert
            )
            let alertAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.Default, handler: nil)
            alertController.addAction(alertAction)
            self.presentViewController(alertController, animated: true, completion: nil)
        })
    }

    @IBAction func switchCameras(sender: UISegmentedControl) {
        var desiredPosition: AVCaptureDevicePosition = _isUsingFrontFacingCamera ? AVCaptureDevicePosition.Back : AVCaptureDevicePosition.Front
        
        for device in AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo) {
            if (device.position == desiredPosition) {
                _previewLayer.session.beginConfiguration()
                let input: AVCaptureInput! = AVCaptureDeviceInput.deviceInputWithDevice(device as AVCaptureDevice, error: nil) as AVCaptureInput
                for oldInput in _previewLayer.session.inputs {
                    _previewLayer.session.removeInput(oldInput as AVCaptureInput)
                }
                _previewLayer.session.addInput(input)
                _videoDataOutput.connectionWithMediaType(AVMediaTypeVideo).enabled = _detectFaces
                _previewLayer.session.commitConfiguration()
                break;
            }
        }
        _isUsingFrontFacingCamera = !_isUsingFrontFacingCamera;

    }

    
    @IBAction func toggleFaces(sender: UISwitch) {
        _detectFaces = sender.on
        //  Set the video capture stream's enabled state accordingly.
        _videoSession.beginConfiguration()
        _videoDataOutput.connectionWithMediaType(AVMediaTypeVideo).enabled = _detectFaces
        _videoSession.commitConfiguration()
        if (_detectFaces) {
            if (_faceDetector == nil) {
                let detectorOptions = [CIDetectorAccuracy:CIDetectorAccuracyLow]
                _faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: detectorOptions)
            }
        }
        else {
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                // clear out any squares currently displaying.
                //self.drawFaceBoxesForFeatures([], clap: CGRect.zeroRect, orientation: UIDeviceOrientation.Portrait)
                self.HideAllFaces()
            })
        }
    }
    
    // main action method to take a still image -- if face detection has been turned on and a face has been detected
    // the square overlay will be composited on top of the captured image and saved to the camera roll
    @IBAction func takePicture(sender: UIBarButtonItem) {
        // Find out the current orientation and tell the still image output.
        let stillImageConnection =  _imageOutput.connectionWithMediaType(AVMediaTypeVideo)
        let curDevOrientation = UIDevice.currentDevice().orientation

        let avOrientationForDeviceOrientation: [UIDeviceOrientation: AVCaptureVideoOrientation] = [
            UIDeviceOrientation.Portrait: AVCaptureVideoOrientation.Portrait,
            UIDeviceOrientation.PortraitUpsideDown: AVCaptureVideoOrientation.PortraitUpsideDown,
            UIDeviceOrientation.LandscapeLeft: AVCaptureVideoOrientation.LandscapeRight,
            UIDeviceOrientation.LandscapeRight: AVCaptureVideoOrientation.LandscapeLeft
        ]
        stillImageConnection.videoOrientation = avOrientationForDeviceOrientation[curDevOrientation]!
        stillImageConnection.videoScaleAndCropFactor = CGFloat(_effectiveScale)
        
        let doingFaceDetection = _detectFaces && (_effectiveScale == 1.0)
        
        // set the appropriate pixel format / image type output setting depending on if we'll need an uncompressed image for
        // the possiblity of drawing the red square over top or if we're just writing a jpeg to the camera roll which is the trival case
        if doingFaceDetection {
            _imageOutput.outputSettings = [kCVPixelBufferPixelFormatTypeKey: kCMPixelFormat_32BGRA]
//            setOutputSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCMPixelFormat_32BGRA]
//        forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
        }
        else {
            _imageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
        }
        //println("Calling captureStillImageAsynchronouslyFromConnection()...")
        _imageOutput.captureStillImageAsynchronouslyFromConnection(stillImageConnection, completionHandler: { (sampleBuffer, error) -> Void in
            //println("captureStillImageAsynchronouslyFromConnection completion handlercalled.")
            if (error != nil) {
                self.displayErrorOnMainQueue(error, message: "Take picture failed")
                return;
            }
            if (doingFaceDetection) {
                // Got an image.
                let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
                let attachmentsUnmanaged: Unmanaged<CFDictionary>? = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, CMAttachmentMode(kCMAttachmentMode_ShouldPropagate))
                var ciImage: CIImage
                //  Using Unmanaged<T>.takeRetainedValue() tells the compiler to automatically release the reference
                if let attachments = attachmentsUnmanaged?.takeRetainedValue() {
//                    let opts = NSDictionary(objectsAndKeys: attachments)
                    ciImage = CIImage(CVPixelBuffer: pixelBuffer, options: attachments as NSDictionary)
                }
                else {
                    ciImage = CIImage(CVPixelBuffer: pixelBuffer, options: nil)
                }
                var imageOptions: Dictionary<String, NSObject>?
                let orientationUnmanaged: Unmanaged<AnyObject>! =  CMGetAttachment(sampleBuffer, kCGImagePropertyOrientation, UnsafeMutablePointer<CMAttachmentMode>.null())
                if let orientation = orientationUnmanaged?.takeUnretainedValue() as? NSNumber {
                    imageOptions = [CIDetectorImageOrientation: orientation]
                }
                //println("Queueing image processing routine to drop frames.")
                // when processing an existing frame we want any new frames to be automatically dropped
                // queueing this block to execute on the videoDataOutputQueue serial queue ensures this
                // see the header doc for setSampleBufferDelegate:queue: for more information
//                dispatch_sync(self._videoDataOutputQueue, { () -> Void in
                    //println("Image processing routine called.")
                    // get the array of CIFeature instances in the given image with a orientation passed in
                    // the detection will be done based on the orientation but the coordinates in the returned features will
                    // still be based on those of the image.
                    let features = self._faceDetector?.featuresInImage(ciImage, options: imageOptions)
                    //println("Calling CreateCGImageFromCVPixelBuffer()...")
                    var srcImage = CreateCGImageFromCVPixelBuffer(pixelBuffer)
                    if (srcImage == nil) {
                        //  Handle error
                        return
                    }
                    
                    //println("Calling newSquareOverlayedImageForFeatures()...")
                    let cgImageResult = newSquareOverlayedImageForFeatures(self._squareImage!,
                        features as [CIFaceFeature], srcImage, curDevOrientation, self._isUsingFrontFacingCamera)
                    
                    let attachmentsRes: Unmanaged<CFDictionary>? = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, CMAttachmentMode(kCMAttachmentMode_ShouldPropagate))
                    if let attachments = attachmentsRes?.takeRetainedValue() {
                        writeCGImageToCameraRoll(cgImageResult, attachments)
                    }
                    else {
                        // Handle error
                    }
//                })
            
            
            }
            else {
                // trivial simple JPEG case
                let jpegData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer)
                let attachmentsRes: Unmanaged<CFDictionary>? = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, CMAttachmentMode(kCMAttachmentMode_ShouldPropagate))
                
                if let attachments = attachmentsRes?.takeRetainedValue() {
                    let library = ALAssetsLibrary()
                    library.writeImageDataToSavedPhotosAlbum(jpegData, metadata: attachments as NSDictionary,
                        completionBlock: { (url, error) -> Void in
                            if (error != nil) {
                                self.displayErrorOnMainQueue(error, message: "Save to camera roll failed")
                            
                        }
                    })
                }


            }
        
        })
        
        
    
    }
    
    
    //  Sample buffer received
    func captureOutput(captureOutput: AVCaptureOutput!,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer!,
        fromConnection connection: AVCaptureConnection!) {
            //  Bail early if appropriate
            if !_detectFaces {
                return
            }
            let pixelBuffer: CVPixelBufferRef = CMSampleBufferGetImageBuffer(sampleBuffer)
            
            let attachmentsUnmanaged: Unmanaged<CFDictionary>! = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, CMAttachmentMode(kCMAttachmentMode_ShouldPropagate))
            if let attachments:CFDictionary = attachmentsUnmanaged?.takeRetainedValue() {
                let ciImage = CIImage(CVPixelBuffer: pixelBuffer, options: attachments as NSDictionary)

                let curDeviceOrientation = UIDevice.currentDevice().orientation
                
//                let exifOrientation: PhotosExif0Row! = _isUsingFrontFacingCamera ? kDeviceOrientationToExifOrientationFront[curDeviceOrientation] : kDeviceOrientationToExifOrientationBack[curDeviceOrientation]
                let exifOrientation: PhotosExif0Row! = kDeviceOrientationToExifOrientation[_isUsingFrontFacingCamera]?[curDeviceOrientation]
                if (exifOrientation == nil) {
                    //  Handle error
                    println("Could not get exif orientation for device orientation \(curDeviceOrientation.rawValue)")
                    return
                }
                let imageOptions = [CIDetectorImageOrientation: exifOrientation.rawValue]
                
                let features = _faceDetector != nil ? _faceDetector.featuresInImage(ciImage, options: imageOptions) : []
                
                // get the clean aperture
                // the clean aperture is a rectangle that defines the portion of the encoded pixel dimensions
                // that represents image data valid for display.
                let fdesc = CMSampleBufferGetFormatDescription(sampleBuffer)
                if fdesc == nil {
                    println("Could not obtain format description from sample")
                    return
                }
                
                let clap: CGRect = CMVideoFormatDescriptionGetCleanAperture(fdesc, Boolean(0) /*originIsTopLeft == false*/)
                //println("CLAP: \(clap.self)")
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    self.drawFaceBoxesForFeatures(features, clap: clap, orientation: curDeviceOrientation)
                })
                
            }
            else {
                println("No attachments found for image.")
                
            }
    }
    
    func captureOutput(captureOutput: AVCaptureOutput!, didDropSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        
    }
    
    func HideAllFaces() {
        // hide all the face layers
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        let sublayers = _previewLayer.sublayers as [CALayer]
        for layer in sublayers {
            if layer.name? == kFaceLayerName {
                layer.hidden = true
            }
        }
        CATransaction.commit()

    }
    
    //  Draws boxes about each face found by the recognizer.
    //
    func drawFaceBoxesForFeatures(features: [AnyObject], clap: CGRect, orientation: UIDeviceOrientation) -> Void
    {
        let sublayers = _previewLayer.sublayers as [CALayer]

        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)

        // hide all the face layers
        for layer in sublayers {
            if layer.name? == kFaceLayerName {
                layer.hidden = true
            }
        }
        if features.count == 0 || clap == CGRect.zeroRect { // bail early
            CATransaction.commit()
            return
        }
        //  Having issues with timing in Swift - so check here if we really want to draw faces or not.
        if !_detectFaces {
            CATransaction.commit()
            return
        }
        //println("clap: \(clap)")

        let parentFrameSize: CGSize = previewView.frame.size
        let gravity: String = _previewLayer.videoGravity
        let isMirrored = _previewLayer.connection.videoMirrored
        let previewBox: CGRect = _previewLayer.frame //videoPreviewBoxForGravity(gravity, parentFrameSize, clap.size)
        //println("Preview box: \(previewBox)")
        for item in features {
            if let ff = item as? CIFaceFeature {
                
                var faceRect: CGRect = ff.bounds
//                println("Feature bounds: \(faceRect)")
                
                /*  UIKit and CoreAnimation coordinates on iOS originate at top left;
                unmirrored CoreImage coordinates also originate at top left but flip x and y.
                In addition, a scale should be applied as the still image from a video is 
                often of a different size than the preview view/layer.
                
                Thus, 
                    Xnew = scaleWidth * Yold
                    Ynew = scaleHeight * Xold
                
                iOS provides a set of affine transform functions that will perform this in one
                step.  In this instance, we want the following affine transform (for unmirrored images):
                
                --                                      --
                |  0            scaleWidth          0    |
                |  scaleHeight      0               0    |
                |  0                0               1    |
                --                                     --
                
                Furthermore, if the image is mirrored, as with a front-facing camera, we want
                    Xnew = -1 * Yold + Width
                    Ynew = scaleHeight * Xold
                
                and the corresponding transform is described by:
                
                --                                      --
                |  0            -scaleWidth   UI width   |
                |  scaleHeight      0               0    |
                |  0                0               1    |
                --                                     --
                
*/
                let widthScaleBy: CGFloat = previewBox.size.width / clap.size.height
                let heightScaleBy: CGFloat = previewBox.size.height / clap.size.width
                var transform = isMirrored ? CGAffineTransformMake(0, heightScaleBy, -widthScaleBy, 0, previewBox.size.width, 0) :
                    CGAffineTransformMake(0, heightScaleBy, widthScaleBy, 0, 0, 0)
                
                faceRect = CGRectApplyAffineTransform(faceRect, transform)
                
                //  Apply the preview origin offset, if any.
                faceRect = CGRectOffset(faceRect, previewBox.origin.x, previewBox.origin.y)

               
                var featureLayer: CALayer!
                
                // Reuse an existing hidden layer if possible
                for layer in sublayers {
                    if layer.name? == kFaceLayerName && layer.hidden {
                        featureLayer = layer
                        layer.hidden = false
                    }
                    if featureLayer != nil { break }
                }
                
                // create a new layer if necessary
                if (featureLayer == nil) {
                    featureLayer = CALayer()
                    featureLayer.contents = _squareImage!.CGImage
                    featureLayer.name = kFaceLayerName
                    _previewLayer.addSublayer(featureLayer)
                }
                featureLayer.frame = faceRect
                //println("Set face rect to \(faceRect)")
                
                //  Transform for the orientation of the device.
                switch orientation {
                case .Portrait:
                    featureLayer.setAffineTransform(RotationTransform(0.0))
                case .PortraitUpsideDown:
                    featureLayer.setAffineTransform(RotationTransform(180.0))
                case .LandscapeLeft:
                    featureLayer.setAffineTransform(RotationTransform(90.0))
                case .LandscapeRight:
                    featureLayer.setAffineTransform(RotationTransform(-90.0))
                case .FaceUp:
                    break
                case .FaceDown:
                    break
                default:
                    break
                    
                }

            } // END for each face feature
            
        } // END for each item
        CATransaction.commit()
    }
    
}

