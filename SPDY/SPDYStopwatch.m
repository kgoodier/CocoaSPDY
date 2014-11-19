//
//  SPDYStopwatch.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier
//

#import <mach/mach_time.h>
#import "SPDYStopwatch.h"

@implementation SPDYStopwatch
{
    SPDYTimeInterval _startTime;
}

static dispatch_once_t __initTimebase;
static double __machTimebaseToSeconds;
static mach_timebase_info_data_t __machTimebase;

+ (void)initialize
{
    dispatch_once(&__initTimebase, ^{
        kern_return_t status = mach_timebase_info(&__machTimebase);
        // TODO: what to do if this fails?
        if (status == KERN_SUCCESS) {
            __machTimebaseToSeconds = (double)__machTimebase.numer / ((double)__machTimebase.denom * 1000000000.0);
        }
    });
}

+ (SPDYTimeInterval)currentSystemTime
{
    uint64_t now = mach_absolute_time();
    return (SPDYTimeInterval)now * __machTimebaseToSeconds;
}

- (id)init
{
    self = [super init];
    if (self) {
        _startTime = [SPDYStopwatch currentSystemTime];
    }
    return self;
}

- (void)reset
{
    _startTime = [SPDYStopwatch currentSystemTime];
}

- (SPDYTimeInterval)elapsedSeconds
{
    return [SPDYStopwatch currentSystemTime] - _startTime;
}

@end
