//
//  CoinExtractor.m
//  PennyCamera
//
//  Created by Peter Kovacs on 7/25/19.
//  Copyright © 2019 Kovapps. All rights reserved.
//

#import <opencv2/opencv.hpp>
#import <optional>

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import "CoinExtractor.h"

static const double kAspectRatio = 1.6;
static const double kAspectRatioInverse = 1 / kAspectRatio;
static const float kMaxCCWAngle = 10.0;
static const float kMinCWAngle = 170.0;

static cv::Mat threshold(const cv::Mat &mat ) {
    cv::Mat gray;
    cv::cvtColor(mat, gray, cv::COLOR_BGRA2GRAY);
    cv::GaussianBlur(gray, gray, cv::Size(3, 3), 0, 0, cv::BORDER_DEFAULT);
    cv::threshold(gray, gray, 243, 255, cv::THRESH_TRUNC);
    cv::adaptiveThreshold(gray, gray, 255, cv::ADAPTIVE_THRESH_GAUSSIAN_C, cv::THRESH_BINARY, 11, -2.0);
    gray = 255 - gray;
    return gray;
}

static std::optional<cv::RotatedRect> findEllipse( const cv::Mat &mat, cv::Rect2f roi ) {
    std::vector<std::vector<cv::Point2i> > contours;
    std::vector<cv::Vec4i> hierarchy; // not actually used.
    std::vector<cv::RotatedRect> ellipses;

    cv::findContours(mat, contours, hierarchy, cv::RETR_CCOMP, cv::CHAIN_APPROX_SIMPLE);

    int aspectRatio = 0, heightTooSmall = 0, widthTooSmall = 0, wrongAngle = 0, tooBig = 0, notEnoughPoints = 0, notContained = 0;
    float maxWidth = std::numeric_limits<float>::min();

    std::for_each( contours.begin(), contours.end(), [&](const std::vector<cv::Point2i>& contour) {
        if( contour.size() >= 5) {
            cv::RotatedRect rect = cv::fitEllipseDirect(contour);
            cv::Rect2f bounding = rect.boundingRect();
            if( rect.size.area() > roi.area() )                                 { ++tooBig; }
            else if( abs(rect.size.width  - roi.width)  > roi.width * 0.25 )    { maxWidth = std::max( maxWidth, rect.size.width); ++widthTooSmall; }
            else if( abs(rect.size.height - roi.height) > roi.height * 0.25 )   { ++heightTooSmall; }
            else if( abs(rect.size.aspectRatio() - kAspectRatio) > 0.1 &&
                     abs(rect.size.aspectRatio() - kAspectRatioInverse) > 0.1 ) { ++aspectRatio; }
            // We'll either get an angle between 0-10° or between 180 - 170°
            else if ((rect.angle > kMaxCCWAngle && rect.angle < kMinCWAngle) ||
                     (rect.angle > 180.0 && rect.angle <= 360.0))               { ++wrongAngle; }
            else if( bounding.tl().x < 0 ||
                     bounding.tl().y < 0.0 ||
                     bounding.br().x > mat.cols ||
                     bounding.br().y > mat.rows )                               { ++notContained; }
            else {
                ellipses.push_back(rect);
            }
        } else { ++notEnoughPoints; }
    });

    auto maxRect = std::max_element(ellipses.begin(), ellipses.end(), [](const auto& a, const auto& b) {
        return a.size.area() < b.size.area();
    });

    if( maxRect != ellipses.end() ) {
        cv::RotatedRect translated(*maxRect);
        translated.center.x += roi.x;
        translated.center.y += roi.y;

        return std::optional<cv::RotatedRect>(translated);
    } else {
        return std::optional<cv::RotatedRect>();
    }
}

static CGRect calculateScaledROI( CGRect roi, CGRect frame, CGSize image ) {
    CGRect translated;
    if( image.width > image.height ) {
        assert( frame.size.width > frame.size.height );

        CGAffineTransform scale = CGAffineTransformMakeScale( image.width / frame.size.width, image.width / frame.size.width );

        frame = CGRectApplyAffineTransform(frame, scale);
        translated = CGRectApplyAffineTransform(roi, scale);
        translated.origin.y += (image.height - frame.size.height) / 2.0;

    } else {
        assert( frame.size.height > frame.size.width );
        CGAffineTransform scale = CGAffineTransformMakeScale( image.height / frame.size.height, image.height / frame.size.height );

        frame = CGRectApplyAffineTransform(frame, scale);
        translated = CGRectApplyAffineTransform(roi, scale);

        translated.origin.x += (image.width - frame.size.width) / 2.0;
    }


    return translated;
}

static cv::Rect2f scaleROI(CGRect roi, CGRect frame, CGSize image) {
    CGRect translated = calculateScaledROI(roi, frame, image);
    return cv::Rect2f(translated.origin.x, translated.origin.y, translated.size.width, translated.size.height);
}

static cv::Mat rotate(const cv::Mat &mat, const cv::RotatedRect &ellipse) {
    cv::Mat result = mat(ellipse.boundingRect());
    // ellipse.angle -> The rotation angle in a clockwise direction. When the angle is 0, 90, 180, 270 etc., the rectangle becomes an up-right rectangle.

    cv::RotatedRect rotatedEllipse(ellipse.center - cv::Point2f(ellipse.boundingRect().tl()), ellipse.size, 0.0);

    // Rotation angle in degrees. Positive values mean counter-clockwise rotation (the coordinate origin is assumed to be the top-left corner).

    float rotation;
    if( ellipse.angle < kMaxCCWAngle ) {
        rotation = ellipse.angle;
    } else {
        rotation = ellipse.angle - 180.0;
    }

    cv::Mat M = cv::getRotationMatrix2D(rotatedEllipse.center, rotation, 1.0);
    cv::warpAffine(result, result, M, ellipse.boundingRect().size());

    return result;
}

static cv::Mat resize(const cv::Mat &mat, size_t height) {
    cv::Mat result;
    cv::Size2f original(mat.cols, mat.rows);
    cv::Size2f size = original * ( (float)height / original.height );

    NSLog(@"RESIZING FROM (%d x %d) -> (%d x %d)", (int)original.width, (int)original.height, (int)size.width, (int)size.height);

    cv::resize(mat, result, size);
    return result;
}

@interface UIImage (OpenCV)
- (cv::Mat)mat;
- (cv::Mat)matGray;
+ (nullable UIImage*)fromMat:(cv::Mat)cvMat;
@end

@implementation CoinExtractor
+ (NSString*)openCVVersionString {
    return [NSString stringWithFormat:@"OpenCV Version %s", CV_VERSION];
}

+ (CGRect)calculateScaledROI:(CGRect)roi frame:(CGRect)frame extent:(CGSize)image {
    return calculateScaledROI(roi, frame, image);
}

+ (UIImage *)drawEllipseOnPixelBuffer:(CVPixelBufferRef)buffer withROI:(CGRect)rect withFrame:(CGRect)frame {
    OSType format = CVPixelBufferGetPixelFormatType(buffer);
    CGRect videoRect = CGRectMake(0.0f, 0.0f, CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer));
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);

    assert(format == kCVPixelFormatType_32BGRA);

    std::optional<cv::RotatedRect> ellipse;

    {
        CVPixelBufferLockBaseAddress(buffer, 0);
        void *baseAddress = CVPixelBufferGetBaseAddress(buffer);
        cv::Mat mat8uc4(videoRect.size.height, videoRect.size.width, CV_8UC4, baseAddress, bytesPerRow);
        cv::Rect2f roi = scaleROI(rect, frame, videoRect.size);
        ellipse = findEllipse(threshold(mat8uc4(roi)), roi);
        CVPixelBufferUnlockBaseAddress(buffer, 0);
    }

    if( ellipse ) {
        // TODO: Invert the transforms used to scale the roi so that we can return an image of frame.size.
        cv::Mat result = cv::Mat(cv::Size2i(videoRect.size.width, videoRect.size.height), CV_8UC4, cv::Scalar(0, 0, 0, 0));
        cv::ellipse(result, ellipse.value(), cv::Scalar(64, 64, 255, 255), 5);

        return [UIImage fromMat:result];
    }

    return nil;
}

+ (UIImage *)captureEllipseOnImage:(UIImage *)image withROI:(CGRect)rect withFrame:(CGRect)frame {
    cv::Mat mat( [image mat] );
    cv::Rect2f roi = scaleROI(rect, frame, image.size);

    std::optional<cv::RotatedRect> ellipse = findEllipse(threshold(mat(roi)), roi);

    // If there is no ellipse, then we'll just make one ourselves based on the roi.
    if( !ellipse ) {
        cv::Point2f center = cv::Point2f(roi.x + roi.width / 2, roi.y + roi.height / 2);
        ellipse = cv::RotatedRect(center, roi.size(), 0.0);
    }

    cv::Mat result;
    cv::Mat channels[4];
    cv::split(mat, channels);
    {
        cv::Mat alpha = cv::Mat(mat.rows, mat.cols, CV_8UC1, cv::Scalar(0));
        cv::ellipse(alpha, ellipse.value(), cv::Scalar(255), -1);
        channels[3] = alpha;
    }
    cv::merge(channels, 4, result);

    assert( result.type() == CV_8UC4 );

    result = rotate(result, ellipse.value());
    result = resize(result, 450);
    return [UIImage fromMat: result];
}

+ (nullable UIImage *)captureMachineOnImage:(nonnull UIImage *)image withROI:(CGRect)rect withFrame:(CGRect)frame {
    static const size_t dx = 24, dy = 60;

    cv::Rect2f roi = scaleROI(rect, frame, image.size);
    cv::Rect2i region = cv::Rect2i( roi.x - dx, roi.y - dy, roi.width + dx * 2, roi.height + dy * 2 );
    cv::Mat mat( [image mat] ), blur, mask(region.height, region.width, CV_8UC1);

    cv::GaussianBlur(mat(region), blur, cv::Size(99, 99), 0, 0, cv::BORDER_DEFAULT);
    cv::rectangle(mask, cv::Point2i(dx, dy), cv::Point2i(region.width - dx, region.height - dy), cv::Scalar(255), -1);
    cv::copyTo(mat(region), blur, mask);

    blur = resize(blur, 450);

    return [UIImage fromMat: blur];
}

@end

@implementation UIImage (OpenCV)

- (cv::Mat)mat {
    assert(self.size.width > 0 && self.size.height > 0);
    assert(self.CGImage != nil || self.CIImage != nil);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat width = self.size.width;
    CGFloat height = self.size.height;

    cv::Mat mat8uc4((int)height, (int)width, CV_8UC4);

    if( self.CGImage) {
        CGContextRef context = CGBitmapContextCreate(mat8uc4.data,
                                                     mat8uc4.cols,
                                                     mat8uc4.rows,
                                                     8,
                                                     mat8uc4.step,
                                                     colorSpace,
                                                     kCGImageAlphaPremultipliedLast |
                                                     kCGBitmapByteOrderDefault);

        CGContextDrawImage(context, CGRectMake(0, 0, width, height), self.CGImage);
        CGContextRelease(context);
    } else {
        static CIContext *context = nil;
        if(!context) {
            context = [CIContext contextWithOptions:@{ kCIContextUseSoftwareRenderer: @NO }];
        }

        CGRect bounds = CGRectMake(0, 0, width, height);
        [context render:self.CIImage toBitmap:mat8uc4.data rowBytes:mat8uc4.step bounds:bounds format:kCIFormatRGBA8 colorSpace:colorSpace];
    }
    CGColorSpaceRelease(colorSpace);

    cv::Mat mat8uc3(width, height, CV_8UC3);
    cv::cvtColor(mat8uc4, mat8uc3, cv::COLOR_RGBA2BGR);

    return mat8uc3;
}

- (cv::Mat)matGray {
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(self.CGImage);
    CGFloat cols = self.size.width;
    CGFloat rows = self.size.height;

    cv::Mat cvMat(rows, cols, CV_8UC1);

    CGContextRef context = CGBitmapContextCreate(cvMat.data,
                                                 cols,
                                                 rows,
                                                 8,
                                                 cvMat.step[0],
                                                 colorSpace,
                                                 kCGImageAlphaNoneSkipLast |
                                                 kCGBitmapByteOrderDefault);

    CGContextDrawImage(context, CGRectMake(0, 0, cols, rows), self.CGImage);
    CGContextRelease(context);

    return cvMat;
}

+ (UIImage*)fromMat:(cv::Mat)cvMat {

    cv::Mat matRGB;

    CGColorSpaceRef colorSpace;

    if (cvMat.elemSize() == 1) {
        colorSpace = CGColorSpaceCreateDeviceGray();
        cv::cvtColor(cvMat, matRGB, cv::COLOR_GRAY2RGBA);
    } else {
        colorSpace = CGColorSpaceCreateDeviceRGB();
        cv::cvtColor(cvMat, matRGB, cv::COLOR_BGRA2RGBA);
    }

    NSData *data = [NSData dataWithBytes:matRGB.data length:matRGB.elemSize() * matRGB.total()];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);

    CGImageRef imageRef = CGImageCreate(matRGB.cols,
                                        matRGB.rows,
                                        8,
                                        8 * matRGB.elemSize(),
                                        matRGB.step[0],
                                        colorSpace,
                                        kCGImageAlphaLast | kCGBitmapByteOrderDefault,
                                        provider,
                                        NULL,
                                        false,
                                        kCGRenderingIntentDefault);

    UIImage *finalImage = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);

    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);

    return finalImage;
}

@end
