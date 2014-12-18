//
//  SPDYMetadata.h
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore
//


#import <Foundation/Foundation.h>
#import "SPDYDefinitions.h"

@interface SPDYMetadata : NSObject
@property (nonatomic, copy) NSString *version;
@property (nonatomic) SPDYStreamId streamId;
@property (nonatomic) NSInteger latencyMs;
@property (nonatomic) NSUInteger txBytes;
@property (nonatomic) NSUInteger rxBytes;
@property (nonatomic) BOOL cellular;
@property (nonatomic) NSUInteger connectedMs;
@property (nonatomic) NSUInteger blockedMs;
@property (nonatomic, copy) NSString *hostAddress;
@property (nonatomic) NSUInteger hostPort;
@property (nonatomic) BOOL viaProxy;

// The following measurements, presented in seconds, use mach_absolute_time() and are point-in-time
// relative to whatever base mach_absolute_time() uses. They are best consumed relative to
// timeSessionConnected, which is always guaranteed to be the smallest value of all these. A value
// of 0 for any of them means it was not set.
@property (nonatomic) SPDYTimeInterval timeSessionConnected;
@property (nonatomic) SPDYTimeInterval timeStreamCreated;
@property (nonatomic) SPDYTimeInterval timeStreamStarted;
@property (nonatomic) SPDYTimeInterval timeStreamLastRequestData;
@property (nonatomic) SPDYTimeInterval timeStreamResponse;
@property (nonatomic) SPDYTimeInterval timeStreamFirstData;
@property (nonatomic) SPDYTimeInterval timeStreamClosed;

- (NSDictionary *)dictionary;

+ (void)setMetadata:(SPDYMetadata *)metadata forAssociatedDictionary:(NSMutableDictionary *)dictionary;
+ (SPDYMetadata *)metadataForAssociatedDictionary:(NSDictionary *)dictionary;

@end
