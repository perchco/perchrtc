//
//  PHVideoSampleView.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2/6/2014.
//  Copyright (c) 2014 Perch Communications. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>

typedef CMSampleBufferRef (^PHVideoSampleRequestBlock)(void);

@class PHSampleBufferView;

@interface PHSampleBufferView : UIView

@property (copy) NSString *videoGravity;

/* Sample provider.
 * The CMSampleBuffer refs provided will be released after they are enqueued for display.
 */
- (void)addSampleProviderWithBlock:(PHVideoSampleRequestBlock)providerBlock inQueue:(dispatch_queue_t)providerQueue;
- (void)stopSampleProvider;

- (void)displaySampleBuffer:(CMSampleBufferRef)sampleBuffer;

- (void)flush;

@end
