//
//  PHFrameConverter.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2/7/2014.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import "PHFrameConverter.h"
#import "libyuv.h"

#import "PHConvert.h"

#import <nighthawk-webrtc/RTCI420Frame.h>
#import <Accelerate/Accelerate.h>

static size_t kFrameConverterBufferPoolHint = 5;

// Determines which technique is used to convert YUV420 frames to BGRA.
// The default is libYUV, but Accelerate can be used on iOS 8 devices.
static BOOL kFrameConverterUseAccelerate = YES;

@interface PHFrameConverter()

@property (nonatomic, assign) CGImageRef frameRef;
@property (nonatomic, assign) CVPixelBufferRef pixelBuffer;
@property (nonatomic, assign) CMSampleBufferRef sampleBuffer;

@property (nonatomic, assign) CGSize videoFrameSize;
@property (nonatomic, strong) NSData *imageData;
@property (nonatomic, assign) PHFrameConverterOutput outputType;

@property (nonatomic, assign) CVPixelBufferPoolRef bufferPool;
@property (nonatomic, assign) CFDictionaryRef bufferPoolAuxAttributes;
@property (nonatomic, assign) CMFormatDescriptionRef outputFormatDescription;
@property (nonatomic, assign) vImage_YpCbCrToARGB *conversionInfo;
@property (nonatomic, assign) BOOL supportsAccelerate;

@end

@implementation PHFrameConverter

#pragma mark - Class

+ (instancetype)converterWithOutput:(PHFrameConverterOutput)output
{
    return [[self alloc] initWithOutput:output];
}

#pragma mark - Initialize & Dealloc

- (instancetype)init
{
    PHFrameConverterOutput recommendedFormat = [[self class] recommendedOutputFormat];
    return [self initWithOutput:recommendedFormat];
}

- (instancetype)initWithOutput:(PHFrameConverterOutput)output
{
    self = [super init];
    if (self) {
        _outputType = output;
        _supportsAccelerate = kFrameConverterUseAccelerate && [[[UIDevice currentDevice] systemVersion] compare:@"8.0" options:NSNumericSearch] != NSOrderedAscending;
        _shouldPreallocateBuffers = NO;

        if (_supportsAccelerate && (output == PHFrameConverterOutputCGImageBackedByCVPixelBuffer || output == PHFrameConverterOutputCMSampleBufferBackedByCVPixelBufferBGRA)) {
            [self prepareForAccelerateConversion];
        }
    }
    return self;
}

- (void)dealloc
{
    [self deleteBuffers];
    [self flushFrame];
    [self unprepareForAccelerateConversion];
    [self teardownPixelBuffer];
}

#pragma mark - Public

- (CFTypeRef)copyConvertedFrame:(RTCI420Frame *)frame
{
    [self flushFrame];

    CFTypeRef frameReturn = NULL;

    if (self.outputType == PHFrameConverterOutputCGImageBackedByNSData)
    {
        [self prepareDataBufferForFrame:frame];

        [self fillData:self.imageData withFrame:frame];

        self.frameRef = [self createCGImageFromFrame:frame backedByData:self.imageData];
    }
    else if (self.outputType == PHFrameConverterOutputCGImageBackedByCVPixelBuffer)
    {
        // Find a pixel buffer.

        CVPixelBufferRef pixelBuffer = [self dequeuePixelBufferForFrame:frame];

        if (pixelBuffer) {
            if (_supportsAccelerate) {
                [self convertFrameVImageYUV:frame toBuffer:pixelBuffer];
            }
            else {
                [self convertFrame:frame toBuffer:pixelBuffer];
            }

            self.frameRef = [self createCGImageFromPixelBufferNoCopy:pixelBuffer];
        }
    }
    else if (self.outputType == PHFrameConverterOutputCGImageCopiedFromCVPixelBuffer)
    {
        [self preparePixelBufferForFrame:frame forceRGB:YES];

        [self convertFrame:frame toBuffer:self.pixelBuffer];

        self.frameRef = [self createCGImageFromPixelBuffer:self.pixelBuffer];
    }
    else if (self.outputType == PHFrameConverterOutputCVPixelBufferCopiedFromSource)
    {
        CVPixelBufferRef pixelBuffer = [self dequeuePixelBufferForFrame:frame];

        if (pixelBuffer) {
            [self copyPlanesFromFrame:frame toPixelBuffer:pixelBuffer];

            self.pixelBuffer = pixelBuffer;
        }
    }
    else if (self.outputType == PHFrameConverterOutputCMSampleBufferBackedByCVPixelBuffer)
    {
        CVPixelBufferRef pixelBuffer = [self dequeuePixelBufferForFrame:frame];

        if (pixelBuffer) {
            [self packPlanesFromFrame:frame toPixelBuffer:pixelBuffer];

            self.sampleBuffer = [self createSampleBufferWithImageBuffer:pixelBuffer];
        }
    }
    else if (self.outputType == PHFrameConverterOutputCMSampleBufferBackedByCVPixelBufferBGRA) {
        CVPixelBufferRef pixelBuffer = [self dequeuePixelBufferForFrame:frame];

        if (pixelBuffer) {
            if (_supportsAccelerate) {
                [self convertFrameVImageYUV:frame toBuffer:pixelBuffer];
            }
            else {
                [self convertFrame:frame toBuffer:pixelBuffer];
            }

            self.sampleBuffer = [self createSampleBufferWithImageBuffer:pixelBuffer];
        }
    }

    if (self.frameRef) {
        frameReturn = self.frameRef;
    }
    else if (self.sampleBuffer) {
        frameReturn = self.sampleBuffer;
    }
    else if (self.pixelBuffer) {
        frameReturn = self.pixelBuffer;
    }

    return frameReturn;
}

- (void)flushFrame
{
    if (_frameRef != NULL) {
//        CGImageRelease(_frameRef);
        _frameRef = NULL;
    }
    if (_sampleBuffer != NULL) {
//        CFRelease(_sampleBuffer);
        _sampleBuffer = NULL;
    }
}

- (BOOL)prepareForSourceDimensions:(CMVideoDimensions)dimensions
{
    OSType format;

    switch (self.outputType) {
        case PHFrameConverterOutputCMSampleBufferBackedByCVPixelBuffer:
        {
            format = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
            break;
        }
        case PHFrameConverterOutputCGImageBackedByCVPixelBuffer:
        case PHFrameConverterOutputCMSampleBufferBackedByCVPixelBufferBGRA:
        {
            format = kCVPixelFormatType_32ARGB;
            break;
        }
        default:
            format = kCVPixelFormatType_32BGRA;
            break;
    }

    if (_bufferPool != NULL) {
        [self deleteBuffers];
    }

    return [self initializeBuffersWithOutputDimensions:dimensions pixelFormat:format retainedBufferCountHint:kFrameConverterBufferPoolHint];
}

#pragma mark - Private

- (vImage_Error)prepareForAccelerateConversion
{
    // Setup the YpCbCr to ARGB conversion.

    if (_conversionInfo != NULL) {
        return kvImageNoError;
    }

    vImage_YpCbCrPixelRange pixelRange = { 0, 128, 255, 255, 255, 1, 255, 0 };
    //    vImage_YpCbCrPixelRange pixelRange = { 16, 128, 235, 240, 255, 0, 255, 0 };
    vImage_YpCbCrToARGB *outInfo = malloc(sizeof(vImage_YpCbCrToARGB));
    vImageYpCbCrType inType = kvImage420Yp8_Cb8_Cr8;
    vImageARGBType outType = kvImageARGB8888;

    vImage_Error error = vImageConvert_YpCbCrToARGB_GenerateConversion(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4, &pixelRange, outInfo, inType, outType, kvImagePrintDiagnosticsToConsole);

    _conversionInfo = outInfo;

    return error;
}

- (void)unprepareForAccelerateConversion
{
    if (_conversionInfo != NULL) {
        free(_conversionInfo);
        _conversionInfo = NULL;
    }
}

- (CVPixelBufferRef)dequeuePixelBufferForFrame:(RTCI420Frame *)frame
{
    CVPixelBufferRef dstPixelBuffer = NULL;

    if ( frame == NULL ) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"NULL frame" userInfo:nil];
        return NULL;
    }

    const CMVideoDimensions srcDimensions = { (int32_t)frame.width, (int32_t)frame.height };
    const CMVideoDimensions dstDimensions = CMVideoFormatDescriptionGetDimensions( _outputFormatDescription );
    if ( srcDimensions.width != dstDimensions.width || srcDimensions.height != dstDimensions.height ) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Invalid pixel buffer dimensions" userInfo:nil];
        return NULL;
    }

    CVReturn err = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes( kCFAllocatorDefault, _bufferPool, _bufferPoolAuxAttributes, &dstPixelBuffer );
    if ( err == kCVReturnWouldExceedAllocationThreshold ) {
        NSLog(@"Pool is out of buffers, dropping frame");
    }
    else if ( err != kCVReturnSuccess) {
        NSLog(@"Error at CVPixelBufferPoolCreatePixelBuffer %d", err);
    }

    return dstPixelBuffer;
}

#pragma mark - BGRA CVPixelBuffer from RTCI420Frame (via libYUV)

- (void)convertFrame:(RTCI420Frame *)frame toBuffer:(CVPixelBufferRef)pixelBufferRef
{
    NSAssert( !CVPixelBufferIsPlanar(pixelBufferRef), @"Can't fill a planar pixel buffer with RGB data!");

	CVPixelBufferLockBaseAddress(pixelBufferRef, 0);

	uint8_t *pxdata = (uint8_t*)CVPixelBufferGetBaseAddress(pixelBufferRef);
    const uint8_t* yPlane = frame.yPlane;
    const uint8_t* uPlane = frame.uPlane;
    const uint8_t* vPlane = frame.vPlane;

    int yStride = (int)frame.yPitch;
    int uStride = (int)frame.uPitch;
    int vStride = (int)frame.vPitch;
    int width = (int)frame.width;
    int height = (int)frame.height;
    int rgbStride = width * 4;
    // multiply chroma strides by 2 as bytesPerRow represents 2x2 subsample
//    int uStride = [[frame.format.bytesPerRow objectAtIndex:1] intValue] * 2;
//    int vStride = [[frame.format.bytesPerRow objectAtIndex:2] intValue] * 2;

    // Use libyuv to convert to the RGB for display purposes
    I420ToARGB(yPlane, yStride,
               vPlane, uStride,
               uPlane, vStride,
               pxdata,
               rgbStride,
               width, height);

	CVPixelBufferUnlockBaseAddress(pixelBufferRef, 0);
}

// TODO: Odd logic / state dependency when determining output format.
- (void)preparePixelBufferForFrame:(RTCI420Frame *)frame forceRGB:(BOOL)forceRGB
{
    // Determine output format.
    OSType destinationPixelFormatType = kCVPixelFormatType_32BGRA;
    if (!forceRGB) {
        destinationPixelFormatType = kCVPixelFormatType_420YpCbCr8Planar;
    }

    // Create CVPixelBuffer if needed.
    size_t width = frame.width;
	size_t height = frame.height;
    CVPixelBufferRef pixelBufferRef = _pixelBuffer;
    BOOL createBuffer = (_videoFrameSize.width != width || _videoFrameSize.height != height);

    if (createBuffer)
    {
        [self teardownPixelBuffer];
        _videoFrameSize = CGSizeMake(width, height);

        NSDictionary *options = [[NSDictionary alloc] initWithObjectsAndKeys:
                                 [NSNumber numberWithBool:forceRGB],
                                 kCVPixelBufferCGImageCompatibilityKey,
                                 [NSNumber numberWithBool:forceRGB],
                                 kCVPixelBufferCGBitmapContextCompatibilityKey,
                                 @{}, kCVPixelBufferIOSurfacePropertiesKey,
                                 nil];

        NSLog(@"Created a pixel buffer sized @ %d x %d Options: %@", (int)width, (int)height, options);

        CVReturn ret = CVPixelBufferCreate(kCFAllocatorDefault,
                                           width, height,
                                           destinationPixelFormatType,
                                           (__bridge CFDictionaryRef) options,
                                           &pixelBufferRef);

        _pixelBuffer = pixelBufferRef;
        NSParameterAssert(ret == kCVReturnSuccess && pixelBufferRef != NULL);
    }
}

- (void)teardownPixelBuffer
{
    if (_pixelBuffer != NULL) {
        CFRelease(_pixelBuffer);
        _pixelBuffer = NULL;
    }
}

#pragma mark - BGRA CGImage (NSData) from RTCI420Frame. libYUV conversion.

- (CGImageRef)createCGImageFromFrame:(RTCI420Frame *)frame backedByData:(NSData *)data
{
    CGImageRef image = NULL;

    size_t imageWidth = frame.width;
    size_t imageHeight = frame.height;
    size_t bitsPerChannel = 8;
    size_t bitsPerPixel = 4 * bitsPerChannel;
    size_t bytesPerRow = 4 * imageWidth;
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Big | kCGImageAlphaNoneSkipLast;
    CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);

    image = CGImageCreate(imageWidth,
                          imageHeight,
                          bitsPerChannel,
                          bitsPerPixel,
                          bytesPerRow,
                          colorspace,
                          bitmapInfo,
                          dataProvider,
                          NULL,
                          YES,
                          kCGRenderingIntentDefault);


    CGDataProviderRelease(dataProvider);
    CGColorSpaceRelease(colorspace);

    return image;
}

- (void)fillData:(NSData *)pixelData withFrame:(RTCI420Frame *)frame
{
    BOOL isBGRA = NO;

    // If the incoming frame is already BGRA, then just copy it straight over.
    if (isBGRA)
    {
        size_t imageSize = frame.yPitch * frame.height;
        void *sourceBytes = (void *)frame.yPlane;
        uint8_t *pxdata = (uint8_t*)[pixelData bytes];
        memcpy(pxdata, sourceBytes, imageSize);
    }
    // If the incoming frame is I420YUV, convert it to RGB
    else
    {
        uint8_t *pxdata = (uint8_t*)[pixelData bytes];
        const uint8_t* yPlane = frame.yPlane;
        const uint8_t* uPlane = frame.uPlane;
        const uint8_t* vPlane = frame.vPlane;

        int yStride = (int)frame.yPitch;
        // multiply chroma strides by 2 as bytesPerRow represents 2x2 subsample
        int uStride = (int)frame.uPitch * 2;
        int vStride = (int)frame.vPitch * 2;

        // Use libyuv to convert to the RGB for display purposes
        I420ToARGB(yPlane, yStride,
                   vPlane, uStride,
                   uPlane, vStride,
                   pxdata,
                   (int)frame.width * 4,
                   (int)frame.width, (int)frame.height);
    }
}

- (void)prepareDataBufferForFrame:(RTCI420Frame *)frame
{
    size_t width = frame.width;
    size_t height = frame.height;
    size_t imageSize = width * height * 4;

    BOOL createData = [self.imageData length] != imageSize;
    if (createData) {
        void *bytes = malloc(imageSize);
        self.imageData = [NSData dataWithBytesNoCopy:bytes length:imageSize freeWhenDone:YES];
    }
}


#pragma mark - CGImage from BGRA CVPixelBuffer

void dataProviderReleaseCallback(void *info, const void *data, size_t size)
{
    CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)info;

    if (pixelBuffer != NULL) {
        CVPixelBufferRelease(pixelBuffer);
    }
    else {
        NSLog(@"No pixel buffer to release!");
    }
}

- (CGImageRef)createCGImageFromPixelBufferNoCopy:(CVPixelBufferRef)imageBuffer
{
    // Create a CVPixelBufferRef filled with BGRA samples from the incoming video frame.
    CGImageRef image = NULL;

    if (imageBuffer == NULL) {
        return image;
    }

    // Lock
    CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);

    // Create a CGImageRef, based on the ARGB video frame
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    size_t bitsPerComponent = 8;
    size_t bitsPerPixel = bitsPerComponent * 4;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Big | kCGImageAlphaNoneSkipLast;
    CFIndex rowBytes = CVPixelBufferGetBytesPerRow(imageBuffer);
    CFIndex totalBytes = rowBytes * height;
    void *bytes = CVPixelBufferGetBaseAddress(imageBuffer);

    // Unlock
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);

    CGDataProviderRef provider = CGDataProviderCreateWithData(imageBuffer, bytes, totalBytes, dataProviderReleaseCallback);

    image = CGImageCreate(width,
                          height,
                          bitsPerComponent,
                          bitsPerPixel,
                          rowBytes,
                          colorSpace,
                          bitmapInfo,
                          provider,
                          NULL,
                          YES,
                          kCGRenderingIntentDefault);

    CGDataProviderRelease(provider);
    CFRelease(colorSpace);

    return image;
}

- (CGImageRef)createCGImageFromPixelBuffer:(CVPixelBufferRef)imageBuffer
{
    // Lock
    CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);

    uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);

    // Unlock
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);

    // Create a CGImageRef from the CVPixelBufferRef
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef newContext = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Big | kCGImageAlphaNoneSkipLast);
    CGImageRef newImage = CGBitmapContextCreateImage(newContext);

    // Memory
    CGContextRelease(newContext);
    CGColorSpaceRelease(colorSpace);

    return newImage;
}


#pragma mark - YUV420 CVPixelBuffer from RTCI420Frame

- (void)copyPlanesFromFrame:(RTCI420Frame *)frame toPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    if (pixelBuffer == NULL) {
        return;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);

    NSUInteger nPlanesSource = 3;
    size_t nPlanesDestination = CVPixelBufferGetPlaneCount(pixelBuffer);

    NSAssert(nPlanesSource == nPlanesDestination, @"Can't copy planes when the source and destination plane layouts differ!");

    size_t widths[3] = {frame.width, frame.chromaWidth, frame.chromaWidth};
    size_t rowBytes[3] = {frame.yPitch, frame.uPitch, frame.vPitch};
    size_t heights[3] = {frame.height, frame.chromaHeight, frame.chromaHeight};
    void *planeData[3] = {(void *)frame.yPlane, (void *)frame.uPlane, (void *)frame.vPlane};

    // Copy each plane accounting for differences in rowBytes between the source and destination.

    for (int i = 0; i < nPlanesSource; i++) {

        size_t sourceRowBytes = rowBytes[i];
        size_t destinationRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, i);
        size_t planeHeight = heights[i];
        size_t planeWidth = widths[i];
        void *sourcePlaneBytes = planeData[i];
        void *destinationPlaneBytes = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, i);
        BOOL rowBytesEqual = sourceRowBytes == destinationRowBytes;
        size_t planeSize = destinationRowBytes * planeHeight;

        if (rowBytesEqual) {
            memcpy(destinationPlaneBytes, sourcePlaneBytes, planeSize);
        }
        else {
            for (int row = 0; row < planeHeight; row++) {
                memcpy(destinationPlaneBytes, sourcePlaneBytes, planeWidth);
                sourcePlaneBytes = sourcePlaneBytes + sourceRowBytes;
                destinationPlaneBytes = destinationPlaneBytes + destinationRowBytes;
            }
        }
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
}

- (vImage_Error)packPlanesFromFrame:(RTCI420Frame *)frame toPixelBuffer:(CVPixelBufferRef)pixelBuffer
{
    if (pixelBuffer == NULL) {
        return kvImageNullPointerArgument;
    }

    vImage_Error packError = kvImageNoError;
    OSType destinationFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    BOOL sourceIsNative = destinationFormat == kCVPixelFormatType_420YpCbCr8Planar || destinationFormat == kCVPixelFormatType_420YpCbCr8PlanarFullRange;
    BOOL canPackSource = destinationFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;

    NSAssert(sourceIsNative || canPackSource, @"Can't pack or copy these pixels!");

    // The source is native, and a copy will suffice.

    if (sourceIsNative) {
        [self copyPlanesFromFrame:frame toPixelBuffer:pixelBuffer];
        return packError;
    }

    // The source is YUV420 planar, and we need to pack its UV planes into YUV420P bi-planar.

    size_t width = frame.width;
    size_t height = frame.height;
    size_t subsampledHeight = frame.chromaHeight;

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);

//    NSDate *start = [NSDate date];

    // Copy the Y-plane

    size_t rowBytesSource = frame.yPitch;
    size_t rowBytesDestination = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    size_t sizeSource = rowBytesSource * height;

    void *yDataSource = (void *)frame.yPlane;
    void *yDataDestination = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    BOOL yBytesEqual = rowBytesSource == rowBytesDestination;

    if (yBytesEqual) {
        memcpy(yDataDestination, yDataSource, sizeSource);
    }
    else {
        for (int row = 0; row < height; row++) {
            memcpy(yDataDestination, yDataSource, width);
            yDataSource = yDataSource + rowBytesSource;
            yDataDestination = yDataDestination + rowBytesDestination;
        }
    }

    // Pack the source U, V planes into one interleaved UV plane.

    size_t uRowBytes = frame.uPitch;
    size_t vRowBytes = frame.vPitch;
    void *uData = (void *)frame.uPlane;
    void *vData = (void *)frame.vPlane;

    size_t uvRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    void *uvData = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);

    // @note: The RTCI420Frame source has unaligned planes, while our destination is properly (64-byte) aligned.
    // Write garbage data to the padded bytes for improved interleaving performance via NEON intrinsics.

    int dstWidth = (int)rowBytesDestination;

    for (int row = 0; row < subsampledHeight; row++) {
        ConvertPlanarUVToPackedRow(uData, vData, uvData, dstWidth);
        uData = uData + uRowBytes;
        vData = vData + vRowBytes;
        uvData = uvData + uvRowBytes;
    }

//    DDLogVerbose(@"Packed in: %f ms", -1000. * [start timeIntervalSinceNow]);

    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    return packError;
}

#pragma mark - CMSampleBuffer (wrapping CVPixelBuffer) from RTCI420Frame

// TODO: Error handling
- (CMSampleBufferRef)createSampleBufferWithImageBuffer:(CVImageBufferRef)imageBuffer
{
    CMSampleBufferRef sampleBuffer = NULL;

    // Pack the image into a sample buffer ref.
    CMVideoFormatDescriptionRef format = NULL;
    OSStatus formatStatus = 0;

    if (_outputFormatDescription != NULL) {
        format = _outputFormatDescription;
    }
    else {
        formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, imageBuffer, &format);
    }

    CMSampleTimingInfo sampleTiming = {
        .duration = kCMTimeInvalid,
        .presentationTimeStamp = CMTimeMakeWithSeconds(CACurrentMediaTime(), 30),
//        .presentationTimeStamp = kCMTimeInvalid,
        .decodeTimeStamp = kCMTimeInvalid
    };

    OSStatus sampleBufferStatus;

    // 

    if (_supportsAccelerate) {
        sampleBufferStatus = CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault,
                                                                      imageBuffer,
                                                                      format,
                                                                      &sampleTiming,
                                                                      &sampleBuffer);
    }
    else {
        sampleBufferStatus = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                                                imageBuffer,
                                                                YES,
                                                                NULL,
                                                                NULL,
                                                                format,
                                                                &sampleTiming,
                                                                &sampleBuffer);
    }

    // Force immediate display of the sample buffer.

    NSMutableDictionary *sampleAttachments = [(NSArray *)CMSampleBufferGetSampleAttachmentsArray( sampleBuffer, true ) firstObject];
    sampleAttachments[(id)kCMSampleAttachmentKey_DisplayImmediately] = @YES;

    // Cleanup

    CFRelease(imageBuffer);

    if (sampleBufferStatus != 0 || formatStatus != 0) {
        NSLog(@"Created CMSampleBuffer with status: %d format status: %d", (int)sampleBufferStatus, (int)formatStatus);
    }

    return sampleBuffer;
}

#pragma mark - YUV420 to RGB Conversion (via Accelerate & vImage)

- (vImage_Error)convertFrameVImageYUV:(RTCI420Frame *)frame toBuffer:(CVPixelBufferRef)pixelBufferRef
{
    if (pixelBufferRef == NULL) {
        return kvImageInvalidParameter;
    }

    // Compute info for interleaved YUV420 source.

    vImagePixelCount width = frame.width;
    vImagePixelCount height = frame.height;
    vImagePixelCount subsampledWidth = frame.chromaWidth;
    vImagePixelCount subsampledHeight = frame.chromaHeight;

    const uint8_t *yPlane = frame.yPlane;
    const uint8_t *uPlane = frame.uPlane;
    const uint8_t *vPlane = frame.vPlane;
    size_t yStride = (size_t)frame.yPitch;
    size_t uStride = (size_t)frame.uPitch;
    size_t vStride = (size_t)frame.vPitch;

    // Create vImage buffers to represent each of the Y, U, and V planes

    vImage_Buffer yPlaneBuffer = {.data = (void *)yPlane, .height = height, .width = width, .rowBytes = yStride};
    vImage_Buffer uPlaneBuffer = {.data = (void *)uPlane, .height = subsampledHeight, .width = subsampledWidth, .rowBytes = uStride};
    vImage_Buffer vPlaneBuffer = {.data = (void *)vPlane, .height = subsampledHeight, .width = subsampledWidth, .rowBytes = vStride};

    // Create a vImage buffer for the destination pixel buffer.

    CVPixelBufferLockBaseAddress(pixelBufferRef, 0);

    void *pixelBufferData = CVPixelBufferGetBaseAddress(pixelBufferRef);
    size_t rowBytes = CVPixelBufferGetBytesPerRow(pixelBufferRef);
    vImage_Buffer destinationImageBuffer = {.data = pixelBufferData, .height = height, .width = width, .rowBytes = rowBytes};

    // Do the conversion.

    uint8_t permuteMap[4] = {3, 2, 1, 0}; // BGRA
    vImage_Error convertError = vImageConvert_420Yp8_Cb8_Cr8ToARGB8888(&yPlaneBuffer, &vPlaneBuffer, &uPlaneBuffer, &destinationImageBuffer, self.conversionInfo, permuteMap, 255, 0);

    CVPixelBufferUnlockBaseAddress(pixelBufferRef, 0);

    return convertError;
}

#pragma mark - Class Methods

+ (PHFrameConverterOutput)recommendedOutputFormat
{
    return PHFrameConverterOutputCGImageBackedByCVPixelBuffer;
}

#pragma mark - Buffer Pools

- (BOOL)initializeBuffersWithOutputDimensions:(CMVideoDimensions)outputDimensions pixelFormat:(OSType)format retainedBufferCountHint:(size_t)clientRetainedBufferCountHint
{
    BOOL success = YES;

    size_t maxRetainedBufferCount = clientRetainedBufferCountHint;
    _bufferPool = createPixelBufferPool( outputDimensions.width, outputDimensions.height, format, (int32_t)maxRetainedBufferCount, self.outputType );
    if ( ! _bufferPool ) {
        NSLog( @"Problem initializing a buffer pool." );
        success = NO;
        goto bail;
    }

    _bufferPoolAuxAttributes = createPixelBufferPoolAuxAttributes( (int32_t)maxRetainedBufferCount );

    if (_shouldPreallocateBuffers) {
        preallocatePixelBuffersInPool( _bufferPool, _bufferPoolAuxAttributes );
    }

    CMFormatDescriptionRef outputFormatDescription = NULL;
    CVPixelBufferRef testPixelBuffer = NULL;
    CVPixelBufferPoolCreatePixelBufferWithAuxAttributes( kCFAllocatorDefault, _bufferPool, _bufferPoolAuxAttributes, &testPixelBuffer );
    if ( ! testPixelBuffer ) {
        NSLog( @"Problem creating a pixel buffer." );
        success = NO;
        goto bail;
    }
    CMVideoFormatDescriptionCreateForImageBuffer( kCFAllocatorDefault, testPixelBuffer, &outputFormatDescription );
    _outputFormatDescription = outputFormatDescription;
    CFRelease( testPixelBuffer );

bail:
    if ( ! success ) {
        [self deleteBuffers];
    }
    return success;
}

- (void)deleteBuffers
{
    NSLog(@"Deleting converter buffer pool.");

    if ( _bufferPool ) {
        CFRelease( _bufferPool );
        _bufferPool = NULL;
    }
    if ( _bufferPoolAuxAttributes ) {
        CFRelease( _bufferPoolAuxAttributes );
        _bufferPoolAuxAttributes = NULL;
    }
    if ( _outputFormatDescription ) {
        CFRelease( _outputFormatDescription );
        _outputFormatDescription = NULL;
    }
}

static CVPixelBufferPoolRef createPixelBufferPool( int32_t width, int32_t height, OSType pixelFormat, int32_t maxBufferCount, PHFrameConverterOutput outputType )
{
    CVPixelBufferPoolRef outputPool = NULL;

    CFMutableDictionaryRef sourcePixelBufferOptions = CFDictionaryCreateMutable( kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks );
    CFNumberRef number = CFNumberCreate( kCFAllocatorDefault, kCFNumberSInt32Type, &pixelFormat );
    CFDictionaryAddValue( sourcePixelBufferOptions, kCVPixelBufferPixelFormatTypeKey, number );
    CFRelease( number );

    number = CFNumberCreate( kCFAllocatorDefault, kCFNumberSInt32Type, &width );
    CFDictionaryAddValue( sourcePixelBufferOptions, kCVPixelBufferWidthKey, number );
    CFRelease( number );

    number = CFNumberCreate( kCFAllocatorDefault, kCFNumberSInt32Type, &height );
    CFDictionaryAddValue( sourcePixelBufferOptions, kCVPixelBufferHeightKey, number );
    CFRelease( number );

    // Round number, 128 is better than 64 for display.

    if (outputType == PHFrameConverterOutputCMSampleBufferBackedByCVPixelBuffer) {

        CFDictionaryAddValue( sourcePixelBufferOptions, kCVPixelBufferBytesPerRowAlignmentKey, (void *)@(128) );
        CFDictionaryAddValue( sourcePixelBufferOptions, kCVPixelBufferPlaneAlignmentKey, (void *)@(128) );

    }

    // @note: In order for rendering to work via AVSampleBufferDisplayLayer IOSurfaces need to be shared across process boundaries.
    // VTDecompressionSession can add this key for you, but if you are creating your own buffer pool it must be added manually.
    // Mac example: https://developer.apple.com/library/mac/samplecode/MultiGPUIOSurface/Introduction/Intro.html#//apple_ref/doc/uid/DTS40010132

    // TODO: Obfuscate IOSurfaceIsGlobal for the app store reviewers, as it is private on iOS (but not Mac).

    ((__bridge NSMutableDictionary *)sourcePixelBufferOptions)[(id)kCVPixelBufferIOSurfacePropertiesKey] = @{ @"IOSurfaceIsGlobal" : @YES };

    number = CFNumberCreate( kCFAllocatorDefault, kCFNumberSInt32Type, &maxBufferCount );
    CFDictionaryRef pixelBufferPoolOptions = CFDictionaryCreate( kCFAllocatorDefault, (const void **)&kCVPixelBufferPoolMinimumBufferCountKey, (const void **)&number, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks );
    CFRelease( number );

    CVPixelBufferPoolCreate( kCFAllocatorDefault, pixelBufferPoolOptions, sourcePixelBufferOptions, &outputPool );

    CFRelease( sourcePixelBufferOptions );
    CFRelease( pixelBufferPoolOptions );
    return outputPool;
}

static CFDictionaryRef createPixelBufferPoolAuxAttributes( int32_t maxBufferCount )
{
    // CVPixelBufferPoolCreatePixelBufferWithAuxAttributes() will return kCVReturnWouldExceedAllocationThreshold if we have already vended the max number of buffers
    NSDictionary *auxAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:[NSNumber numberWithInt:maxBufferCount], (id)kCVPixelBufferPoolAllocationThresholdKey, nil];
    return (__bridge_retained CFDictionaryRef)auxAttributes;
}

static void preallocatePixelBuffersInPool( CVPixelBufferPoolRef pool, CFDictionaryRef auxAttributes )
{
    // Preallocate buffers in the pool, since this is for real-time display/capture
    NSMutableArray *pixelBuffers = [[NSMutableArray alloc] init];
    while ( 1 )
    {
        CVPixelBufferRef pixelBuffer = NULL;
        OSStatus err = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes( kCFAllocatorDefault, pool, auxAttributes, &pixelBuffer );

        if ( err == kCVReturnWouldExceedAllocationThreshold ) {
            break;
        }
        assert( err == noErr );

        [pixelBuffers addObject:(__bridge_transfer id)pixelBuffer];
    }
    [pixelBuffers removeAllObjects];
}

@end
