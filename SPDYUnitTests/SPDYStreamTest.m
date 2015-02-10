//  SPDYStreamTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#import <SenTestingKit/SenTestingKit.h>
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYStream.h"
#import "SPDYMockSessionTestBase.h"
#import "SPDYMockURLProtocolClient.h"

@interface SPDYStreamTest : SPDYMockSessionTestBase
@end

@implementation SPDYStreamTest

static const NSUInteger kTestDataLength = 128;
static NSMutableData *_uploadData;
static NSThread *_streamThread;

+ (void)setUp
{
    [super setUp];

    _uploadData = [[NSMutableData alloc] initWithCapacity:kTestDataLength];
    for (int i = 0; i < kTestDataLength; i++) {
        [_uploadData appendBytes:&(uint32_t){ arc4random() } length:4];
    }
//    SecRandomCopyBytes(kSecRandomDefault, kTestDataLength, _uploadData.mutableBytes);
}

- (void)testStreamingWithData
{
    NSMutableData *producedData = [[NSMutableData alloc] initWithCapacity:kTestDataLength];
    SPDYStream *spdyStream = [SPDYStream new];
    spdyStream.data = _uploadData;

    while(spdyStream.hasDataAvailable) {
        [producedData appendData:[spdyStream readData:10 error:nil]];
    }

    STAssertTrue([producedData isEqualToData:_uploadData], nil);
}

- (void)testStreamingWithStream
{
    SPDYMockStreamDelegate *mockDelegate = [SPDYMockStreamDelegate new];
    SPDYStream *spdyStream = [SPDYStream new];
    spdyStream.delegate = mockDelegate;
    spdyStream.dataStream = [[NSInputStream alloc] initWithData:_uploadData];

    dispatch_semaphore_t main = dispatch_semaphore_create(0);
    dispatch_semaphore_t alt = dispatch_semaphore_create(0);
    mockDelegate.callback = ^{
        dispatch_semaphore_signal(main);
    };

    STAssertTrue([NSThread isMainThread], @"dispatch must occur from main thread");
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        STAssertFalse([NSThread isMainThread], @"stream must be scheduled off main thread");

        [spdyStream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

        // Run off-thread runloop
        while(dispatch_semaphore_wait(main, DISPATCH_TIME_NOW)) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, YES);
        }
        dispatch_semaphore_signal(alt);
    });

    // Run main thread runloop
    while(dispatch_semaphore_wait(alt, DISPATCH_TIME_NOW)) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, YES);
    }

    STAssertTrue([mockDelegate.data isEqualToData:_uploadData], nil);
}

#define SPDYAssertStreamError(errorDomain, errorCode) do { \
    STAssertTrue(_mockURLProtocolClient.calledDidFailWithError, nil); \
    STAssertNotNil(_mockURLProtocolClient.lastError, nil); \
    STAssertEqualObjects(_mockURLProtocolClient.lastError.domain, (errorDomain), nil); \
    STAssertEquals(_mockURLProtocolClient.lastError.code, (errorCode), nil); \
} while (0)

- (void)testMergeHeadersCollisionDoesAbort
{
    SPDYStream *stream = [self createStream];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
            @":status":@"200", @":version":@"http/1.1"};
    NSDictionary *headersDup = @{@":scheme":@"http"};

    [stream mergeHeaders:headers];
    STAssertFalse(_mockURLProtocolClient.calledDidFailWithError, nil);

    [stream mergeHeaders:headersDup];
    SPDYAssertStreamError(SPDYStreamErrorDomain, SPDYStreamProtocolError);
}

- (void)testReceiveResponseMissingStatusCodeDoesAbort
{
    SPDYStream *stream = [self createStream];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
            @":version":@"http/1.1"};

    [stream mergeHeaders:headers];
    [stream didReceiveResponse];
    SPDYAssertStreamError(NSURLErrorDomain, NSURLErrorBadServerResponse);
}

- (void)testReceiveResponseInvalidStatusCodeDoesAbort
{
    SPDYStream *stream = [self createStream];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
                              @":status":@"99", @":version":@"http/1.1"};

    [stream mergeHeaders:headers];
    [stream didReceiveResponse];
    SPDYAssertStreamError(NSURLErrorDomain, NSURLErrorBadServerResponse);
}

- (void)testReceiveResponseMissingVersionDoesAbort
{
    SPDYStream *stream = [self createStream];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
                              @":status":@"200"};

    [stream mergeHeaders:headers];
    [stream didReceiveResponse];
    SPDYAssertStreamError(NSURLErrorDomain, NSURLErrorBadServerResponse);
}

- (void)testReceiveResponseDoesSucceed
{
    SPDYStream *stream = [self createStream];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
                              @":status":@"200", @":version":@"http/1.1", @"Header1":@"Value1",
                              @"HeaderMany":@[@"ValueMany1", @"ValueMany2"]};

    [stream mergeHeaders:headers];
    [stream didReceiveResponse];
    STAssertTrue(_mockURLProtocolClient.calledDidReceiveResponse, nil);

    NSHTTPURLResponse *response = _mockURLProtocolClient.lastResponse;
    STAssertNotNil(response, nil);

    // Note: metadata adds a header
    STAssertTrue(response.allHeaderFields.count <= (NSUInteger)3, nil);
    STAssertEqualObjects(response.allHeaderFields[@"Header1"], @"Value1", nil);
    STAssertEqualObjects(response.allHeaderFields[@"HeaderMany"], @"ValueMany1, ValueMany2", nil);
}

- (void)testReceiveResponseWithLocationDoesRedirect
{
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/init"]];
    _URLRequest.SPDYPriority = 3;
    _URLRequest.HTTPMethod = @"POST";
    _URLRequest.SPDYBodyFile = @"bodyfile.txt";
    _URLRequest.SPDYDeferrableInterval = 1.0;

    SPDYStream *stream = [self createStream];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
                              @":status":@"200", @":version":@"http/1.1", @"Header1":@"Value1",
                              @"location":@"newpath"};
    NSURL *redirectUrl = [NSURL URLWithString:@"http://mocked/newpath"];

    [stream mergeHeaders:headers];
    [stream didReceiveResponse];
    STAssertTrue(_mockURLProtocolClient.calledWasRedirectedToRequest, nil);

    STAssertEqualObjects(_mockURLProtocolClient.lastRedirectedRequest.URL.absoluteString, redirectUrl.absoluteString, nil);
    STAssertEquals(_mockURLProtocolClient.lastRedirectedRequest.SPDYPriority, (NSUInteger)3, nil);
    STAssertEqualObjects(_mockURLProtocolClient.lastRedirectedRequest.HTTPMethod, @"POST", nil);
    STAssertEqualObjects(_mockURLProtocolClient.lastRedirectedRequest.SPDYBodyFile, @"bodyfile.txt", nil);
    STAssertEquals(_mockURLProtocolClient.lastRedirectedRequest.SPDYDeferrableInterval, 1.0, nil);

    STAssertEqualObjects(((NSHTTPURLResponse *)_mockURLProtocolClient.lastRedirectResponse).allHeaderFields[@"Header1"], @"Value1", nil);
}

- (void)testReceiveResponseWithLocationAnd303DoesRedirect
{
    // Test status code, method, SPDYBodyStream property, and host location change
    NSInputStream *inputStream = [NSInputStream inputStreamWithFileAtPath:@"foo"];
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/init"]];
    _URLRequest.HTTPMethod = @"POST";
    _URLRequest.SPDYBodyStream = inputStream;

    SPDYStream *stream = [self createStream];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
                              @":status":@"303", @":version":@"http/1.1", @"Header1":@"Value1",
                              @"location":@"https://mocked2/newpath"};
    NSURL *redirectUrl = [NSURL URLWithString:@"https://mocked2/newpath"];

    [stream mergeHeaders:headers];
    [stream didReceiveResponse];
    STAssertTrue(_mockURLProtocolClient.calledWasRedirectedToRequest, nil);

    STAssertEqualObjects(_mockURLProtocolClient.lastRedirectedRequest.URL.absoluteString, redirectUrl.absoluteString, nil);
    STAssertEqualObjects(_mockURLProtocolClient.lastRedirectedRequest.HTTPMethod, @"GET", @"expect GET after 303");  // 303 means GET
    STAssertNil(_mockURLProtocolClient.lastRedirectedRequest.SPDYBodyStream, nil);  // GET request must not have a body
}

@end
