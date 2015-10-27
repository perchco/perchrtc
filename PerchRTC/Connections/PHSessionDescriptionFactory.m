//
//  PHSessionDescriptionFactory.m
//  PerchRTC
//
//  Created by Christopher Eagleston on 2015-01-17.
//  Copyright (c) 2015 Perch Communications. All rights reserved.
//

#import "PHSessionDescriptionFactory.h"

#import "RTCMediaConstraints.h"
#import "RTCPair.h"
#import "RTCSessionDescription.h"

@implementation PHSessionDescriptionFactory

#pragma mark - Public

// In the AppRTC example optional offer contraints are nil, but with Talky they include the data channels.
+ (RTCMediaConstraints *)offerConstraints
{
    return [self offerConstraintsRestartIce:NO];
}

+ (RTCMediaConstraints *)offerConstraintsRestartIce:(BOOL)restartICE;
{
    NSArray *optional = nil;

    if (restartICE) {
        RTCPair *icePair = [[RTCPair alloc] initWithKey:@"IceRestart" value:@"true"];
        optional = @[icePair];
    }

    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:[self mandatoryConstraints]
                                                                             optionalConstraints:optional];

    return constraints;
}

+ (RTCMediaConstraints *)connectionConstraints
{
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:[self mandatoryConstraints]
                                                                             optionalConstraints:[self optionalConstraints]];
    return constraints;
}

+ (RTCMediaConstraints *)videoConstraints
{
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:nil];
    return constraints;
}

+ (RTCMediaConstraints *)videoConstraintsForFormat:(PHVideoFormat)videoFormat
{
    NSArray *videoConstraints = [self constraintsForVideoFormat:videoFormat];
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:videoConstraints optionalConstraints:nil];
    return constraints;
}

+ (RTCSessionDescription *)conditionedSessionDescription:(RTCSessionDescription *)sessionDescription
                                              audioCodec:(PHAudioCodec)audioCodec
                                              videoCodec:(PHVideoCodec)videoCodec
                                            videoBitRate:(NSUInteger)videoBitRate
                                            audioBitRate:(NSUInteger)audioBitRate
{
    NSString *sdpString = nil;

    // Audio

    if (audioCodec == PHAudioCodecOpus) {
        sdpString = sessionDescription.description;
    }
    else {
        sdpString = [self preferISACSimple:sessionDescription.description];
    }

    // Video

    if (videoCodec == PHVideoCodecH264) {
        sdpString = [self preferH264:sdpString];
    }
    else {
        sdpString = [self preferVP8:sdpString];
    }

    // Bandwidth

    sdpString = [self constrainedSessionDescription:sdpString videoBandwidth:videoBitRate audioBandwidth:audioBitRate];

    return [[RTCSessionDescription alloc] initWithType:sessionDescription.type sdp:sdpString];
}

#pragma mark - Private

+ (NSArray *)constraintsForVideoFormat:(PHVideoFormat)format
{
    RTCPair *maxWidth = [[RTCPair alloc] initWithKey:@"maxWidth" value:[NSString stringWithFormat:@"%d", format.dimensions.width]];
    RTCPair *maxHeight = [[RTCPair alloc] initWithKey:@"maxHeight" value:[NSString stringWithFormat:@"%d", format.dimensions.height]];
    RTCPair *minWidth = [[RTCPair alloc] initWithKey:@"minWidth" value:@"240"];
    RTCPair *minHeight = [[RTCPair alloc] initWithKey:@"minHeight" value:@"160"];

    return @[maxWidth, maxHeight, minWidth, minHeight];
}

+ (NSArray *)mandatoryConstraints
{
    RTCPair *audioPair = [[RTCPair alloc] initWithKey:@"OfferToReceiveAudio" value:@"true"];
    RTCPair *videoPair = [[RTCPair alloc] initWithKey:@"OfferToReceiveVideo" value:@"true"];

    return @[ audioPair, videoPair ];
}

+ (NSArray *)optionalConstraints
{
    NSArray *optionalConstraints = @[[[RTCPair alloc] initWithKey:@"internalSctpDataChannels" value:@"true"],
                                     [[RTCPair alloc] initWithKey:@"DtlsSrtpKeyAgreement" value:@"true"]];
    return optionalConstraints;
}

+ (NSString *)preferISACSimple:(NSString *)sdp
{
    // TODO: @chris This is a hacky fix, and should made more robust.

    return [sdp stringByReplacingOccurrencesOfString:@"111 103" withString:@"103 111"];
}

+ (NSString *)preferVideoCodec:(NSString *)codec inSDP:(NSString *)sdpString
{
    NSString *lineSeparator = @"\n";
    NSString *mLineSeparator = @" ";
    // Copied from PeerConnectionClient.java.
    // TODO(tkchin): Move this to a shared C++ file.
    NSMutableArray *lines = [NSMutableArray arrayWithArray:[sdpString componentsSeparatedByString:lineSeparator]];
    NSInteger mLineIndex = -1;
    NSString *codecRtpMap = nil;
    // a=rtpmap:<payload type> <encoding name>/<clock rate>
    // [/<encoding parameters>]
    NSString *pattern = [NSString stringWithFormat:@"^a=rtpmap:(\\d+) %@(/\\d+)+[\r]?$", codec];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:0
                                                                             error:nil];
    for (NSInteger i = 0; (i < lines.count) && (mLineIndex == -1 || !codecRtpMap); ++i) {
        NSString *line = lines[i];
        if ([line hasPrefix:@"m=video"]) {
            mLineIndex = i;
            continue;
        }
        NSTextCheckingResult *codecMatches = [regex firstMatchInString:line
                                                               options:0
                                                                 range:NSMakeRange(0, line.length)];
        if (codecMatches) {
            codecRtpMap = [line substringWithRange:[codecMatches rangeAtIndex:1]];
            continue;
        }
    }

    if (mLineIndex == -1) {
        NSLog(@"No m=video line, so can't prefer %@", codec);
        return sdpString;
    }

    if (!codecRtpMap) {
        NSLog(@"No rtpmap for %@", codec);
        return sdpString;
    }

    NSArray *origMLineParts = [lines[mLineIndex] componentsSeparatedByString:mLineSeparator];

    if (origMLineParts.count > 3) {
        NSMutableArray *newMLineParts = [NSMutableArray arrayWithCapacity:origMLineParts.count];
        NSInteger origPartIndex = 0;

        // Format is: m=<media> <port> <proto> <fmt> ...
        [newMLineParts addObject:origMLineParts[origPartIndex++]];
        [newMLineParts addObject:origMLineParts[origPartIndex++]];
        [newMLineParts addObject:origMLineParts[origPartIndex++]];
        [newMLineParts addObject:codecRtpMap];

        for (; origPartIndex < origMLineParts.count; ++origPartIndex) {
            if (![codecRtpMap isEqualToString:origMLineParts[origPartIndex]]) {
                [newMLineParts addObject:origMLineParts[origPartIndex]];
            }
        }
        NSString *newMLine = [newMLineParts componentsJoinedByString:mLineSeparator];
        [lines replaceObjectAtIndex:mLineIndex withObject:newMLine];
    }
    else {
        NSLog(@"Wrong SDP media description format: %@", lines[mLineIndex]);
    }

    return [lines componentsJoinedByString:lineSeparator];
}

+ (NSString *)preferVP8:(NSString *)sdpString
{
    return [self preferVideoCodec:@"VP8" inSDP:sdpString];
}

+ (NSString *)preferH264:(NSString *)sdpString
{
    return [self preferVideoCodec:@"H264" inSDP:sdpString];
}

+ (NSString *)constrainedSessionDescription:(NSString *)sdp videoBandwidth:(NSUInteger)videoBandwidth audioBandwidth:(NSUInteger)audioBandwidth
{
    // Modify the SDP's video & audio media sections to restrict the maximum bandwidth used.

    NSString *mAudioLinePattern = @"m=audio(.*)";
    NSString *mVideoLinePattern = @"m=video(.*)";

    NSString *constraintedSDP = [self limitBandwidth:sdp withPattern:mAudioLinePattern maximum:audioBandwidth];
    constraintedSDP = [self limitBandwidth:constraintedSDP withPattern:mVideoLinePattern maximum:videoBandwidth];

    return constraintedSDP;
}

+ (NSString *)limitBandwidth:(NSString *)sdp withPattern:(NSString *)mLinePattern maximum:(NSUInteger)bandwidthLimit
{
    NSString *cLinePattern = @"c=IN(.*)";
    NSError *error = nil;
    NSRegularExpression *mRegex = [[NSRegularExpression alloc] initWithPattern:mLinePattern options:0 error:&error];
    NSRegularExpression *cRegex = [[NSRegularExpression alloc] initWithPattern:cLinePattern options:0 error:&error];
    NSRange mLineRange = [mRegex rangeOfFirstMatchInString:sdp options:NSMatchingWithoutAnchoringBounds range:NSMakeRange(0, [sdp length])];
    NSRange cLineSearchRange = NSMakeRange(mLineRange.location + mLineRange.length, [sdp length] - (mLineRange.location + mLineRange.length));
    NSRange cLineRange = [cRegex rangeOfFirstMatchInString:sdp options:NSMatchingWithoutAnchoringBounds range:cLineSearchRange];

    NSString *cLineString = [sdp substringWithRange:cLineRange];
    NSString *bandwidthString = [NSString stringWithFormat:@"b=AS:%d", (int)bandwidthLimit];

    return [sdp stringByReplacingCharactersInRange:cLineRange
                                        withString:[NSString stringWithFormat:@"%@\n%@", cLineString, bandwidthString]];
}


@end
