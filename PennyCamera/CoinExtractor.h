//
//  CoinExtractor.h
//  PennyCamera
//
//  Created by Peter Kovacs on 7/25/19.
//  Copyright © 2019 Kovapps. All rights reserved.
//

#ifndef CoinExtractor_h
#define CoinExtractor_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreServices/CoreServices.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <AVKit/AVKit.h>

@interface CoinExtractor : NSObject
+ (nonnull NSString*)openCVVersionString;
+ (nullable UIImage *)drawEllipseOnCIImage:(nonnull CIImage *)image withContext:(nonnull CIContext*)context withROI:(CGRect)rect withFrame:(CGRect)frame;
+ (nullable UIImage *)drawEllipseOnImage:(nonnull UIImage *)image withROI:(CGRect)rect withFrame:(CGRect)frame;
+ (nullable UIImage *)drawEllipseOnPixelBuffer:(nonnull CVPixelBufferRef)buffer withROI:(CGRect)rect withFrame:(CGRect)frame;
+ (nullable UIImage *)captureEllipseOnImage:(nonnull UIImage *)image withROI:(CGRect)rect withFrame:(CGRect)frame;
+ (CGRect)calculateScaledROI:(CGRect) roi frame:(CGRect)frame extent:(CGSize)image;

@end


#endif /* CoinExtractor_h */
