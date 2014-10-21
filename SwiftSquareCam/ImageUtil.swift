
//  ImageUtil.swift
//  SwiftSquareCam
//
//  Created by Joseph Schwartz on 9/23/14.
//  Copyright (c) 2014 Joseph Schwartz. All rights reserved.
//

import Foundation
import UIKit
import CoreImage
import ImageIO
import AssetsLibrary
import AVFoundation

let kOrientationToDegreesFront: [UIDeviceOrientation: CGFloat] = [
    .Portrait: -90,
    .PortraitUpsideDown: 90,
    .LandscapeLeft: 180,
    .LandscapeRight: 0,
    .FaceUp: 0,
    .FaceDown: 0
]

let kOrientationToDegreesBack: [UIDeviceOrientation: CGFloat] = [
    .Portrait: -90,
    .PortraitUpsideDown: 90,
    .LandscapeLeft: 0,
    .LandscapeRight: 180,
    .FaceUp: 0,
    .FaceDown: 0
]

/* kCGImagePropertyOrientation values
The intended display orientation of the image. If present, this key is a CFNumber value with the same value as defined
by the TIFF and EXIF specifications -- see enumeration of integer constants.
The value specified where the origin (0,0) of the image is located. If not present, a value of 1 is assumed.

used when calling featuresInImage: options: The value for this key is an integer NSNumber from 1..8 as found in kCGImagePropertyOrientation.
If present, the detection will be done based on that orientation but the coordinates in the returned features will still be based on those of the image. */

enum PhotosExif0Row: Int {
    case TOP_0COL_LEFT			= 1 //   1  =  0th row is at the top, and 0th column is on the left (THE DEFAULT).
    case TOP_0COL_RIGHT			= 2 //   2  =  0th row is at the top, and 0th column is on the right.
    case BOTTOM_0COL_RIGHT      = 3 //   3  =  0th row is at the bottom, and 0th column is on the right.
    case BOTTOM_0COL_LEFT       = 4 //   4  =  0th row is at the bottom, and 0th column is on the left.
    case LEFT_0COL_TOP          = 5 //   5  =  0th row is on the left, and 0th column is the top.
    case RIGHT_0COL_TOP         = 6 //   6  =  0th row is on the right, and 0th column is the top.
    case RIGHT_0COL_BOTTOM      = 7 //   7  =  0th row is on the right, and 0th column is the bottom.
    case LEFT_0COL_BOTTOM       = 8  //   8  =  0th row is on the left, and 0th column is the bottom.
}

let kDeviceOrientationToExifOrientationFront: [UIDeviceOrientation: PhotosExif0Row] = [
    .Portrait: .RIGHT_0COL_TOP,
    .PortraitUpsideDown: .LEFT_0COL_BOTTOM,
    .LandscapeLeft: .BOTTOM_0COL_RIGHT,
    .LandscapeRight: .TOP_0COL_LEFT
]

let kDeviceOrientationToExifOrientationBack: [UIDeviceOrientation: PhotosExif0Row] = [
    .Portrait: .RIGHT_0COL_TOP,
    .PortraitUpsideDown: .LEFT_0COL_BOTTOM,
    .LandscapeLeft: .TOP_0COL_LEFT,
    .LandscapeRight: .BOTTOM_0COL_RIGHT
]

//  Maps a Bool, representing whether the front facing camera is being used, to the correct
//  dictionary that itself maps the device orientation to the correcnt EXIF orientation.
let kDeviceOrientationToExifOrientation: [Bool: [UIDeviceOrientation: PhotosExif0Row]] = [
    true: kDeviceOrientationToExifOrientationFront,
    false: kDeviceOrientationToExifOrientationBack
]

func DegreesToRadians(degrees:CGFloat) -> CGFloat {
    return degrees * CGFloat(M_PI) / CGFloat(180.0)
}

func RotationTransform(degrees:Float) -> CGAffineTransform
{
    return CGAffineTransformMakeRotation(DegreesToRadians(CGFloat(degrees)))
}


// create a CGImage with provided pixel buffer, pixel buffer must be uncompressed kCVPixelFormatType_32ARGB or kCVPixelFormatType_32BGRA
func CreateCGImageFromCVPixelBuffer(pixelBuffer:CVPixelBufferRef) -> CGImage!
{
    var err: OSStatus = noErr
    var bitmapInfo: CGBitmapInfo
    var image: CGImage!
    
    CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
    var sourcePixelFormat: OSType = CVPixelBufferGetPixelFormatType( pixelBuffer )
    if ( kCVPixelFormatType_32ARGB == Int(sourcePixelFormat) ) {
        bitmapInfo = CGBitmapInfo(CGBitmapInfo.ByteOrder32Big.rawValue | CGImageAlphaInfo.NoneSkipFirst.rawValue)
    }
    else if ( kCVPixelFormatType_32BGRA == Int(sourcePixelFormat) ) {
        bitmapInfo = CGBitmapInfo(CGBitmapInfo.ByteOrder32Little.rawValue | CGImageAlphaInfo.NoneSkipFirst.rawValue)
    }
    else {
        return nil // -95014; // only uncompressed pixel formats
    }
    
    let width: UInt = CVPixelBufferGetWidth( pixelBuffer )
    let height: UInt = CVPixelBufferGetHeight( pixelBuffer )
    let sourceRowBytes: UInt = CVPixelBufferGetBytesPerRow( pixelBuffer );
    let sourceBaseAddr: UnsafeMutablePointer<Void>  = CVPixelBufferGetBaseAddress( pixelBuffer );
    //println("Pixel buffer info - w:\(width) h:\(height) BytesPerRow:\(sourceRowBytes) BaseAddr:\(sourceBaseAddr)")
    
    let colorspace = CGColorSpaceCreateDeviceRGB();
    let context = CGBitmapContextCreate(sourceBaseAddr, width, height, 8, sourceRowBytes, colorspace, bitmapInfo)
    if (context != nil) {
        image = CGBitmapContextCreateImage(context)
    }
    else {
        println("CreateCGImageFromCVPixelBuffer():  Failed to create bitmap context")
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0)
    
    return image;
}

func CreateCGBitmapContextForSize(size: CGSize) -> CGContextRef
{
    let colorSpace:CGColorSpace! = CGColorSpaceCreateDeviceRGB();
    let bytesPerRow: UInt = UInt(size.width) * 4
    let bitsPerComponent: UInt = 8
  
    let bitmapInfo = CGBitmapInfo(CGImageAlphaInfo.PremultipliedLast.rawValue)
    let context = CGBitmapContextCreate(nil, UInt(size.width), UInt(size.height), bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo)
    
    CGContextSetAllowsAntialiasing(context, false);
    return context;
}

extension UIImage {
    func imageRotatedByDegrees(degrees:CGFloat) -> UIImage {
        // calculate the size of the rotated view's containing box for our drawing space
        let rotatedViewBox = UIView(frame: CGRectMake(0, 0, self.size.width, self.size.height))
        let t: CGAffineTransform = CGAffineTransformMakeRotation(DegreesToRadians(degrees));
        rotatedViewBox.transform = t;
        let rotatedSize = rotatedViewBox.frame.size;
        //[rotatedViewBox release];
        
        // Create the bitmap context
        UIGraphicsBeginImageContext(rotatedSize);
        let bitmap: CGContextRef = UIGraphicsGetCurrentContext();
        
        // Move the origin to the middle of the image so we will rotate and scale around the center.
        CGContextTranslateCTM(bitmap, rotatedSize.width/2, rotatedSize.height/2);
        
        // Rotate the image context
        CGContextRotateCTM(bitmap, DegreesToRadians(degrees));
        
        // Now, draw the rotated/scaled image into the context
        CGContextScaleCTM(bitmap, 1.0, -1.0);
        CGContextDrawImage(bitmap, CGRectMake(-self.size.width / 2, -self.size.height / 2, self.size.width, self.size.height), self.CGImage);
        
        let newImage: UIImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return newImage;
    }
}

func newSquareOverlayedImageForFeatures (
    squareImage: UIImage,
    features: [CIFaceFeature],
    backgroundImage: CGImageRef,
    orientation: UIDeviceOrientation,
    isFrontFacing: Bool) -> CGImageRef
{
    var returnImage: CGImageRef!
    let w  = Int(CGImageGetWidth(backgroundImage))
    let h  = Int(CGImageGetHeight(backgroundImage))
    let backgroundImageRect = CGRect(x:0, y:0, width: w, height:h)
    
    var bitmapContext: CGContextRef! = CreateCGBitmapContextForSize(backgroundImageRect.size)
    CGContextClearRect(bitmapContext, backgroundImageRect);
    CGContextDrawImage(bitmapContext, backgroundImageRect, backgroundImage);

    //  Use dictionaries to look up the rotation corresponding to the given orientation
    if let rotationDegrees = isFrontFacing ?
        kOrientationToDegreesFront[orientation] : kOrientationToDegreesBack[orientation] {
    
        let rotatedSquareImage = squareImage.imageRotatedByDegrees(rotationDegrees)
        
        // features found by the face detector
        for ff in features {
            let faceRect = ff.bounds
            CGContextDrawImage(bitmapContext, faceRect, rotatedSquareImage.CGImage);
        }
        returnImage = CGBitmapContextCreateImage(bitmapContext)
        //CGContextRelease (bitmapContext);
        

    }
    return returnImage;
}

// utility routine used after taking a still image to write the resulting image to the camera roll
func writeCGImageToCameraRoll (cgImage: CGImageRef, metadata: CFDictionary) -> Bool
{
    var destinationData: CFMutableDataRef = CFDataCreateMutable(kCFAllocatorDefault, 0)

    let destination: CGImageDestinationRef! = CGImageDestinationCreateWithData(destinationData,
        "public.jpeg",
        1,
        nil)
    assert(destination != nil)
    
    let JPEGCompQuality: Float = 0.85 // JPEGHigherQuality
    //  The following no longer works in XCode 6.1; the CFString! type is not hashable.
    //let optionsDict = [kCGImageDestinationLossyCompressionQuality: JPEGCompQuality]
    var key: NSString = kCGImageDestinationLossyCompressionQuality
    let optionsDict = [key: JPEGCompQuality]
//    var keys: UnsafeMutablePointer<UnsafePointer<Void>>
//    var key = kCGImageDestinationLossyCompressionQuality as UnsafePointer<Void>
//    var val:Float = JPEGCompQuality
//    var optionsDict: CFDictionary! = CFDictionaryCreate(kCFAllocatorDefault, &key, &val, 1, nil, nil)
    CGImageDestinationAddImage( destination, cgImage, optionsDict )
    var success = CGImageDestinationFinalize( destination )
    
    assert(success == true)
    
    let library = ALAssetsLibrary()
    let data = NSData(data:destinationData)
    library.writeImageDataToSavedPhotosAlbum(data, metadata: metadata as NSDictionary, nil)
    return success;
}

