//
//  SPDYServerPushTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Klemen Verdnik on 6/10/14.
//  Modified by Kevin Goodier on 9/19/14.
//

#import <SenTestingKit/SenTestingKit.h>
#import "SPDYOrigin.h"
#import "SPDYSession.h"
#import "SPDYSocket+SPDYSocketMock.h"
#import "SPDYFrame.h"
#import "SPDYProtocol.h"
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYMockFrameEncoderDelegate.h"
#import "SPDYMockFrameDecoderDelegate.h"
#import "SPDYMockSessionTestBase.h"
#import "SPDYMockURLProtocolClient.h"

@interface SPDYServerPushTest : SPDYMockSessionTestBase
@end

@implementation SPDYServerPushTest
{
}

#pragma mark Test Helpers

- (void)setUp
{
    [super setUp];
}

- (void)tearDown
{
    [super tearDown];
}

#pragma mark Early push error cases tests

- (void)testSYNStreamWithStreamIDZeroRespondsWithSessionError
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Send SYN_STREAM from server to client
    [self mockServerSynStreamWithId:0 last:NO];

    // If a client receives a server push stream with stream-id 0, it MUST issue a session error
    // (Section 2.4.2) with the status code PROTOCOL_ERROR.
    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)2, nil);
    STAssertTrue([_mockDecoderDelegate.framesReceived[0] isKindOfClass:[SPDYGoAwayFrame class]], nil);
    STAssertTrue([_mockDecoderDelegate.framesReceived[1] isKindOfClass:[SPDYRstStreamFrame class]], nil);
    STAssertEquals(((SPDYGoAwayFrame *)_mockDecoderDelegate.framesReceived[0]).statusCode, SPDY_SESSION_PROTOCOL_ERROR, nil);
    STAssertEquals(((SPDYGoAwayFrame *)_mockDecoderDelegate.framesReceived[0]).lastGoodStreamId, (SPDYStreamId)0, nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[1]).statusCode, SPDY_STREAM_PROTOCOL_ERROR, nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[1]).streamId, (SPDYStreamId)1, nil);
}

- (void)testSYNStreamWithUnidirectionalFlagUnsetRespondsWithSessionError
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Simulate a server Tx stream SYN_STREAM request (opening a push stream) that's associated
    // with the stream that the client created.
    SPDYSynStreamFrame *synStreamFrame = [[SPDYSynStreamFrame alloc] init];
    synStreamFrame.streamId = 2;
    synStreamFrame.unidirectional = NO;
    synStreamFrame.last = NO;
    synStreamFrame.headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/pushed",
            @":status":@"200", @":version":@"http/1.1", @"PushHeader":@"PushValue"};
    synStreamFrame.associatedToStreamId = 1;

    [_testEncoderDelegate clear];
    [_testEncoder encodeSynStreamFrame:synStreamFrame error:nil];
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];

    // @@@ Confirm this is right behavior
    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)2, nil);
    STAssertTrue([_mockDecoderDelegate.framesReceived[0] isKindOfClass:[SPDYGoAwayFrame class]], nil);
    STAssertTrue([_mockDecoderDelegate.framesReceived[1] isKindOfClass:[SPDYRstStreamFrame class]], nil);
    STAssertEquals(((SPDYGoAwayFrame *)_mockDecoderDelegate.framesReceived[0]).statusCode, SPDY_SESSION_PROTOCOL_ERROR, nil);
    STAssertEquals(((SPDYGoAwayFrame *)_mockDecoderDelegate.framesReceived[0]).lastGoodStreamId, (SPDYStreamId)0, nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[1]).statusCode, SPDY_STREAM_PROTOCOL_ERROR, nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[1]).streamId, (SPDYStreamId)1, nil);
}

- (void)testSYNStreamWithAssociatedStreamIdZeroRespondsWithSessionError
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Send SYN_STREAM from server to client
    SPDYSynStreamFrame *synStreamFrame = [[SPDYSynStreamFrame alloc] init];
    synStreamFrame.streamId = 2;
    synStreamFrame.unidirectional = YES;
    synStreamFrame.last = NO;
    synStreamFrame.headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/pushed",
            @":status":@"200", @":version":@"http/1.1", @"PushHeader":@"PushValue"};
    synStreamFrame.associatedToStreamId = 0;
    [_testEncoderDelegate clear];
    STAssertTrue([_testEncoder encodeSynStreamFrame:synStreamFrame error:nil] > 0, nil);
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];

    // @@@ Confirm this is right behavior
    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)2, nil);
    STAssertTrue([_mockDecoderDelegate.framesReceived[0] isKindOfClass:[SPDYGoAwayFrame class]], nil);
    STAssertTrue([_mockDecoderDelegate.framesReceived[1] isKindOfClass:[SPDYRstStreamFrame class]], nil);
    STAssertEquals(((SPDYGoAwayFrame *)_mockDecoderDelegate.framesReceived[0]).statusCode, SPDY_SESSION_PROTOCOL_ERROR, nil);
    STAssertEquals(((SPDYGoAwayFrame *)_mockDecoderDelegate.framesReceived[0]).lastGoodStreamId, (SPDYStreamId)0, nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[1]).statusCode, SPDY_STREAM_PROTOCOL_ERROR, nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[1]).streamId, (SPDYStreamId)1, nil);
}

- (void)testSYNStreamWithNoSchemeHeaderRespondsWithReset
 {
     // Exchange initial SYN_STREAM and SYN_REPLY
     [self mockSynStreamAndReplyWithId:1 last:NO];

     NSDictionary *headers = @{/*@":scheme":@"http", */@":host":@"mocked", @":path":@"/pushed"};
     [self mockServerSynStreamWithId:2 last:NO headers:headers];

     // When a client receives a SYN_STREAM from the server without a the ':host', ':scheme', and
     // ':path' headers in the Name/Value section, it MUST reply with a RST_STREAM with error
     // code HTTP_PROTOCOL_ERROR.
     STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)1, nil);
     STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]], nil);
     STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).statusCode, SPDY_STREAM_PROTOCOL_ERROR, nil);
     STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).streamId, (SPDYStreamId)2, nil);
 }

- (void)testSYNStreamAndAHeadersFrameWithDuplicatesRespondsWithReset
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Send SYN_STREAM from server to client
    [self mockServerSynStreamWithId:2 last:NO];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"hello", @"PushHeader2":@"PushValue2"};
    [self mockServerHeadersFrameWithId:2 headers:headers last:NO];

    // If the server sends a HEADER frame containing duplicate headers with a previous HEADERS
    // frame for the same stream, the client must issue a stream error (Section 2.4.2) with error
    // code PROTOCOL ERROR.
    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)1, nil);
    STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]], nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).statusCode, SPDY_STREAM_PROTOCOL_ERROR, nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).streamId, (SPDYStreamId)2, nil);
}

#pragma mark Simple push callback tests

- (void)testSYNStreamWithStreamIDNonZeroMakesResponseCallback
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Send SYN_STREAM from server to client
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];

    SPDYMockURLProtocolClient *pushClient = [self attachToPushRequestWithUrl:@"http://mocked/pushed"].client;
    STAssertTrue(pushClient.calledDidReceiveResponse, nil);
    STAssertFalse(pushClient.calledDidLoadData, nil);
    STAssertFalse(pushClient.calledDidFailWithError, nil);
    STAssertFalse(pushClient.calledDidFinishLoading, nil);

    NSHTTPURLResponse *pushResponse = pushClient.lastResponse;
    STAssertEqualObjects(pushResponse.URL.absoluteString, @"http://mocked/pushed", nil);
    STAssertEquals(pushResponse.statusCode, 200, nil);
    STAssertEqualObjects([pushResponse.allHeaderFields valueForKey:@"PushHeader"], @"PushValue", nil);
}

- (void)testSYNStreamWithStreamIDNonZeroPostsNotification
{
    SPDYMockURLProtocolClient __block *pushClient = nil;

    [[NSNotificationCenter defaultCenter] addObserverForName:SPDYPushRequestReceivedNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        STAssertTrue([note.userInfo[@"request"] isKindOfClass:[NSURLRequest class]], nil);

        NSURLRequest *request = note.userInfo[@"request"];
        STAssertNotNil(request, nil);
        STAssertEqualObjects(request.URL.absoluteString, @"http://mocked/pushed", nil);

        pushClient = [self attachToPushRequest:request].client;
    }];

    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Send SYN_STREAM from server to client. Notification posted at this point.
    [self mockServerSynStreamWithId:2 last:NO];
    STAssertNotNil(pushClient, nil);
    STAssertFalse(pushClient.calledDidReceiveResponse, nil);

    // Send HEADERS from server to client
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    STAssertTrue(pushClient.calledDidReceiveResponse, nil);
    STAssertFalse(pushClient.calledDidLoadData, nil);
    STAssertFalse(pushClient.calledDidFailWithError, nil);
    STAssertFalse(pushClient.calledDidFinishLoading, nil);
    
    NSHTTPURLResponse *pushResponse = pushClient.lastResponse;
    STAssertEqualObjects(pushResponse.URL.absoluteString, @"http://mocked/pushed", nil);
    STAssertEquals(pushResponse.statusCode, 200, nil);
    STAssertEqualObjects([pushResponse.allHeaderFields valueForKey:@"PushHeader"], @"PushValue", nil);

}

- (void)testSYNStreamAfterAssociatedStreamClosesRespondsWithGoAway
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:NO];

    // Close original
    [self mockServerDataFrameWithId:1 length:1 last:YES];

    // Send SYN_STREAM from server to client
    [self mockServerSynStreamWithId:2 last:NO];

    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)1, nil);
    STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYGoAwayFrame class]], nil);
}

- (void)testSYNStreamsAndAssociatedStreamClosingDidCompleteWithMetadata
{
    [self mockSynStreamAndReplyWithId:1 last:NO];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    SPDYMockURLProtocolClient *pushClient2 = [self attachToPushRequestWithUrl:@"http://mocked/pushed"].client;

    // Send another SYN_STREAM from server to client
    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/pushed4"};
    [self mockServerSynStreamWithId:4 last:NO headers:headers];
    [self mockServerHeadersFrameForPushWithId:4 last:YES];
    SPDYMockURLProtocolClient *pushClient4 = [self attachToPushRequestWithUrl:@"http://mocked/pushed4"].client;

    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)0, nil);
    STAssertTrue(_mockURLProtocolClient.calledDidReceiveResponse, nil);
    STAssertFalse(_mockURLProtocolClient.calledDidFinishLoading, nil);
    STAssertTrue(pushClient2.calledDidReceiveResponse, nil);
    STAssertFalse(pushClient2.calledDidFinishLoading, nil);
    STAssertTrue(pushClient4.calledDidReceiveResponse, nil);
    STAssertTrue(pushClient4.calledDidFinishLoading, nil);

    SPDYMetadata *metadata = [SPDYProtocol metadataForResponse:pushClient4.lastResponse];
    STAssertNotNil(metadata, nil);

    // Close original
    [self mockServerDataFrameWithId:1 length:1 last:YES];
    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)0, nil);
    STAssertTrue(_mockURLProtocolClient.calledDidFinishLoading, nil);
    STAssertFalse(pushClient2.calledDidFinishLoading, nil);

    // Close push 1
    [self mockServerDataFrameWithId:2 length:2 last:YES];
    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)0, nil);
    STAssertTrue(pushClient2.calledDidFinishLoading, nil);
}

#if 0

- (void)testSYNStreamClosesAfterHeadersMakesCompletionBlockCallback
{
    _mockExtendedDelegate.testSetsPushResponseDataDelegate = NO;

    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReply];

    // Send SYN_STREAM from server to client with 'last' bit set.
    [self mockServerSynStreamWithId:2 last:YES];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    STAssertTrue([self waitForAnyCallbackOrFrame], nil);  // for extended delegate
    STAssertNotNil(_mockExtendedDelegate.lastPushResponse, nil);

    // Got the completion block callback indicating push response is done?
    STAssertTrue([self waitForAnyCallbackOrFrame], nil);
    STAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushResponse, nil);
    STAssertEquals(_mockPushResponseDataDelegate.lastCompletionData.length, (NSUInteger)0, nil);
    STAssertNil(_mockPushResponseDataDelegate.lastCompletionError, nil);
}

- (void)testSYNStreamClosesAfterDataWithDelayedExtendedCallbackMakesCompletionBlockCallback
{
    _mockExtendedDelegate.testSetsPushResponseCache = [[NSURLCache alloc] init];

    // Send server SYN_STREAM, then send all data, before scheduling the run loop and
    // allowing the extended delegate callback to happen. Should be all ok.
    [self mockSynStreamAndReply];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    [self mockServerDataFrameWithId:2 length:1 last:YES];
    STAssertTrue([self waitForAnyCallbackOrFrame], nil);
    STAssertTrue([self waitForAnyCallbackOrFrame], nil);

    STAssertNotNil(_mockExtendedDelegate.lastPushResponse, nil);
    STAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushResponse, nil);
    STAssertEquals(_mockPushResponseDataDelegate.lastCompletionData.length, (NSUInteger)1, nil);
    STAssertNil(_mockPushResponseDataDelegate.lastCompletionError, nil);
}

- (void)testSYNStreamWithDataMakesCompletionBlockCallback
{
    // Disable delegate and cache
    _mockExtendedDelegate.testSetsPushResponseDataDelegate = nil;
    _mockExtendedDelegate.testSetsPushResponseCache = nil;

    // Initial mainline SYN_STREAM, SYN_REPLY, server SYN_STREAM exchanges
    [self mockSynStreamAndReply];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    STAssertTrue([self waitForAnyCallbackOrFrame], nil);
    STAssertNotNil(_mockExtendedDelegate.lastPushResponse, nil);

    // Send DATA frame, verify callback made
    [self mockServerDataFrameWithId:2 length:100 last:YES];
    STAssertTrue([self waitForAnyCallbackOrFrame], nil);
    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)0, nil);  // no errors
    STAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushResponse, nil);
    STAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushRequest, nil);
    STAssertNotNil(_mockPushResponseDataDelegate.lastCompletionData, nil);
    STAssertEquals(_mockPushResponseDataDelegate.lastCompletionData.length, (NSUInteger)100, nil);
    STAssertNil(_mockPushResponseDataDelegate.lastCompletionError, nil);

    // Some sanity checks
    STAssertEqualObjects(_mockExtendedDelegate.lastPushResponse, _mockPushResponseDataDelegate.lastCompletionPushResponse, nil);
    STAssertEqualObjects(_mockExtendedDelegate.lastPushRequest, _mockPushResponseDataDelegate.lastCompletionPushRequest, nil);
}

 - (void)testSYNStreamWithChunkedDataMakesCompletionBlockCallback
 {
     // Disable delegate
     _mockExtendedDelegate.testSetsPushResponseDataDelegate = nil;
     [self mockPushResponseWithTwoDataFrames];

     STAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushResponse, nil);
     STAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushRequest, nil);
     STAssertNotNil(_mockPushResponseDataDelegate.lastCompletionData, nil);
     STAssertEquals(_mockPushResponseDataDelegate.lastCompletionData.length, (NSUInteger)201, nil);
     STAssertNil(_mockPushResponseDataDelegate.lastCompletionError, nil);
}

- (void)testSYNStreamClosedRespondsWithResetAndMakesCompletionBlockCallback
{
    // Initial mainline SYN_STREAM, SYN_REPLY, server SYN_STREAM exchanges
    [self mockSynStreamAndReply];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    STAssertTrue([self waitForAnyCallbackOrFrame], nil);
    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)0, nil);  // no errors

    // Cancel it
    // @@@ Uh, how to do this?
    STAssertTrue([self waitForAnyCallbackOrFrame], nil);

    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)1, nil);
    STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]], nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).statusCode, SPDY_STREAM_CANCEL, nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).streamId, (SPDYStreamId)2, nil);

    STAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushResponse, nil);
    STAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushRequest, nil);
    STAssertNil(_mockPushResponseDataDelegate.lastCompletionData, nil);
    STAssertNotNil(_mockPushResponseDataDelegate.lastCompletionError, nil);
}

- (void)testSYNStreamWithChunkedDataMakesDataDelegateCallbacks
{
    // Disable completion block
    _mockExtendedDelegate.testSetsPushResponseCompletionBlock = nil;

    // Initial mainline SYN_STREAM, SYN_REPLY, server SYN_STREAM exchanges
    [self mockSynStreamAndReply];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    STAssertTrue([self waitForAnyCallbackOrFrame], nil);
    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)0, nil);  // no errors
    STAssertNotNil(_mockExtendedDelegate.lastPushResponse, nil);

    // Send DATA frame, verify callback made
    [self mockServerDataFrameWithId:2 length:100 last:NO];
    STAssertTrue([self waitForAnyCallbackOrFrame], nil);
    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)0, nil);  // no errors
    STAssertNotNil(_mockPushResponseDataDelegate.lastRequest, nil);
    STAssertNotNil(_mockPushResponseDataDelegate.lastData, nil);
    STAssertEquals(_mockPushResponseDataDelegate.lastData.length, (NSUInteger)100, nil);

    // Send last DATA frame
    [self mockServerDataFrameWithId:2 length:101 last:YES];
    STAssertTrue([self waitForAnyCallbackOrFrame], nil);
    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)0, nil);  // no errors
    STAssertNotNil(_mockPushResponseDataDelegate.lastRequest, nil);
    STAssertNotNil(_mockPushResponseDataDelegate.lastData, nil);
    STAssertEquals(_mockPushResponseDataDelegate.lastData.length, (NSUInteger)101, nil);

    // Runloop may have scheduled the final didComplete callback before we could stop it. But
    // if not, wait for it.
    if (_mockPushResponseDataDelegate.lastMetadata == nil) {
        STAssertTrue([self waitForAnyCallbackOrFrame], nil);
    }
    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)0, nil);  // no errors
    STAssertNotNil(_mockPushResponseDataDelegate.lastMetadata, nil);
    STAssertEqualObjects(_mockPushResponseDataDelegate.lastMetadata[SPDYMetadataVersionKey], @"3.1", nil);
    STAssertEqualObjects(_mockPushResponseDataDelegate.lastMetadata[SPDYMetadataStreamIdKey], @"2", nil);
    STAssertTrue([_mockPushResponseDataDelegate.lastMetadata[SPDYMetadataStreamRxBytesKey] integerValue] > 0, nil);
    STAssertTrue([_mockPushResponseDataDelegate.lastMetadata[SPDYMetadataStreamTxBytesKey] integerValue] == 0, nil);

    // Some sanity checks
    STAssertEqualObjects(_mockExtendedDelegate.lastPushRequest, _mockPushResponseDataDelegate.lastRequest, nil);
    STAssertNil(_mockPushResponseDataDelegate.lastError, nil);
}

- (void)testSYNStreamWithChunkedDataMakesDataDelegateAndCompletionBlockCallbacks
{
    // Disable caching
    _mockExtendedDelegate.testSetsPushResponseCache = nil;

    // Enable both completion block and delegate (default)
    [self mockPushResponseWithTwoDataFrames];

    // Verify last chunk received
    STAssertEquals(_mockPushResponseDataDelegate.lastData.length, (NSUInteger)101, nil);

    // Ensure both happened
    STAssertNotNil(_mockPushResponseDataDelegate.lastCompletionPushResponse, nil);
    STAssertNil(_mockPushResponseDataDelegate.lastCompletionError, nil);
    STAssertEquals(_mockPushResponseDataDelegate.lastCompletionData.length, (NSUInteger)201, nil);
    STAssertNil(_mockPushResponseDataDelegate.lastError, nil);
    STAssertNotNil(_mockPushResponseDataDelegate.lastMetadata, nil);
}

- (void)testSYNStreamWithChunkedDataAndCustomCacheCachesResponse
{
    // Enabled caching only
    _mockExtendedDelegate.testSetsPushResponseDataDelegate = nil;
    _mockExtendedDelegate.testSetsPushResponseCompletionBlock = nil;
    _mockExtendedDelegate.testSetsPushResponseCache = [[NSURLCache alloc] init];

    // Make a new request, don't use the NSURLRequest that got pushed to us
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];

    // Sanity check
    NSCachedURLResponse *response = [_mockExtendedDelegate.testSetsPushResponseCache cachedResponseForRequest:request];
    STAssertNil(response, nil);

    [self mockPushResponseWithTwoDataFrames];

    // Ensure neither callback happened
    STAssertNil(_mockPushResponseDataDelegate.lastCompletionPushResponse, nil);
    STAssertNil(_mockPushResponseDataDelegate.lastMetadata, nil);

    response = [_mockExtendedDelegate.testSetsPushResponseCache cachedResponseForRequest:request];
    STAssertNotNil(response, nil);
    STAssertEquals(response.data.length, (NSUInteger)201, nil);
    STAssertEqualObjects(((NSHTTPURLResponse *)response.response).allHeaderFields[@"PushHeader"], @"PushValue", nil);
}

- (void)testSYNStreamWithChunkedDataAndDelegateSetsNilCacheDoesNotCacheResponse
{
    // Enable nothing, but we still make the completion callback in didReceiveResponse
    _mockExtendedDelegate.testSetsPushResponseDataDelegate = nil;
    _mockExtendedDelegate.testSetsPushResponseCompletionBlock = nil;
    _mockExtendedDelegate.testSetsPushResponseCache = nil;

    // Sanity check
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];
    NSCachedURLResponse *response = [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
    STAssertNil(response, nil);

    [self mockPushResponseWithTwoDataFrames];

    response = [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
    STAssertNil(response, nil);
}

- (void)testSYNStreamWithChunkedDataAndDefaultCacheAndNoDelegateCachesResponse
{
    // Disable extended delegate
    [_URLRequest setExtendedDelegate:nil inRunLoop:nil forMode:nil];
    _protocolRequest = [[SPDYProtocol alloc] initWithRequest:_URLRequest cachedResponse:nil client:nil];

    // Sanity check
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];
    NSCachedURLResponse *response = [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
    STAssertNil(response, nil);

    // No callbacks to wait for
    [self mockSynStreamAndReply];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    [self mockServerDataFrameWithId:2 length:100 last:NO];
    [self mockServerDataFrameWithId:2 length:101 last:YES];

    response = [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
    STAssertNotNil(response, nil);
    STAssertEquals(response.data.length, (NSUInteger)201, nil);
    STAssertEqualObjects(((NSHTTPURLResponse *)response.response).allHeaderFields[@"PushHeader"], @"PushValue", nil);
}

#endif

#pragma mark Headers-related push tests

- (void)testSYNStreamAndAHeadersFrameMergesValues
{
    [self mockSynStreamAndReplyWithId:1 last:NO];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    SPDYMockURLProtocolClient *pushClient = [self attachToPushRequestWithUrl:@"http://mocked/pushed"].client;

    STAssertTrue(pushClient.calledDidReceiveResponse, nil);
    STAssertEqualObjects([pushClient.lastResponse.allHeaderFields valueForKey:@"PushHeader"], @"PushValue", nil);
    STAssertEqualObjects([pushClient.lastResponse.allHeaderFields valueForKey:@"PushHeader2"], nil, nil);

    // Send HEADERS frame
    NSDictionary *headers = @{@"PushHeader2":@"PushValue2"};
    [self mockServerHeadersFrameWithId:2 headers:headers last:NO];

    // TODO: no way to expose new headers to URLProtocolClient, can't verify presence of new header
    // except to say nothing crashed here.
}

- (void)testSYNStreamAndAHeadersFrameAfterDataIgnoresValues
{
    [self mockSynStreamAndReplyWithId:1 last:NO];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameForPushWithId:2 last:NO];
    SPDYMockURLProtocolClient *pushClient = [self attachToPushRequestWithUrl:@"http://mocked/pushed"].client;
    STAssertTrue(pushClient.calledDidReceiveResponse, nil);

    // Send DATA frame
    [self mockServerDataFrameWithId:2 length:100 last:NO];
    STAssertTrue(pushClient.calledDidLoadData, nil);

    // Send last HEADERS frame
    NSDictionary *headers = @{@"PushHeader2":@"PushValue2"};
    [self mockServerHeadersFrameWithId:2 headers:headers last:YES];

    // Ensure stream was closed and callback made
    STAssertTrue(pushClient.calledDidFinishLoading, nil);

    // TODO: no way to expose new headers to URLProtocolClient, can't verify absence of new header.
}

#if 0

#pragma mark Cache-related tests

- (void)testSYNStreamWithChunkedDataDoesNotCacheWhenSuggestedResponseIsNil
{
    _mockExtendedDelegate.testSetsPushResponseCache = [[NSURLCache alloc] init];
    _mockPushResponseDataDelegate.willCacheShouldReturnNil = YES;

    // Make a new request, don't use the NSURLRequest that got pushed to us
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];

    [self mockPushResponseWithTwoDataFrames];

    STAssertNotNil(_mockPushResponseDataDelegate.lastWillCacheSuggestedResponse, nil);

    NSCachedURLResponse *response = [_mockExtendedDelegate.testSetsPushResponseCache cachedResponseForRequest:request];
    STAssertNil(response, nil);
}

- (void)testSYNStreamWithChunkedDataDoesCacheSuggestedResponse
{
    _mockExtendedDelegate.testSetsPushResponseCache = [[NSURLCache alloc] init];

    // Make a new request, don't use the NSURLRequest that got pushed to us
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];

    [self mockPushResponseWithTwoDataFrames];

    STAssertNotNil(_mockPushResponseDataDelegate.lastWillCacheSuggestedResponse, nil);
    STAssertEqualObjects(_mockExtendedDelegate.lastPushResponse, _mockPushResponseDataDelegate.lastWillCacheSuggestedResponse.response, nil);

    NSCachedURLResponse *response = [_mockExtendedDelegate.testSetsPushResponseCache cachedResponseForRequest:request];
    STAssertNotNil(response, nil);
    STAssertEquals(response.data.length, (NSUInteger)201, nil);
    STAssertEqualObjects(((NSHTTPURLResponse *)response.response).allHeaderFields[@"PushHeader"], @"PushValue", nil);
}

- (void)testSYNStreamWithChunkedDataDoesCacheCustomSuggestedResponse
{
    //_mockExtendedDelegate.testSetsPushResponseCache = [[NSURLCache alloc] init];
    NSURLCache *URLCache = [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024
                                                         diskCapacity:20 * 1024 * 1024
                                                             diskPath:nil];
    _mockExtendedDelegate.testSetsPushResponseCache = URLCache;

    [self mockPushResponseWithTwoDataFramesWithId:2];
    STAssertNotNil(_mockPushResponseDataDelegate.lastWillCacheSuggestedResponse, nil);
    STAssertEqualObjects(_mockExtendedDelegate.lastPushResponse, _mockPushResponseDataDelegate.lastWillCacheSuggestedResponse.response, nil);
    NSCachedURLResponse *lastCachedResponse = _mockPushResponseDataDelegate.lastWillCacheSuggestedResponse;

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];
    NSCachedURLResponse *response = [_mockExtendedDelegate.testSetsPushResponseCache cachedResponseForRequest:request];
    STAssertEquals(response.data.length, (NSUInteger)201, nil);

    NSCachedURLResponse *newCachedResponse = [[NSCachedURLResponse alloc]
            initWithResponse:lastCachedResponse.response
                        data:[NSMutableData dataWithLength:1]   // mutated
                    userInfo:nil
               storagePolicy:_mockPushResponseDataDelegate.lastWillCacheSuggestedResponse.storagePolicy];

    _mockPushResponseDataDelegate.willCacheReturnOverride = newCachedResponse;

    // Do it a again. First one was just to grab a response.
    [self mockPushResponseWithTwoDataFramesWithId:4];

    response = [_mockExtendedDelegate.testSetsPushResponseCache cachedResponseForRequest:request];
    STAssertEquals(response.data.length, (NSUInteger)1, nil);
    STAssertEqualObjects(((NSHTTPURLResponse *)response.response).allHeaderFields[@"PushHeader"], @"PushValue", nil);
}

- (void)testSYNStreamWithChunkedDataDoesNotCache500Response
{
    _mockExtendedDelegate.testSetsPushResponseCache = [[NSURLCache alloc] init];

    NSDictionary *headers = @{@":status":@"500", @":version":@"http/1.1", @"PushHeader":@"PushValue"};
    [self mockSynStreamAndReply];
    [self mockServerSynStreamWithId:2 last:NO];
    [self mockServerHeadersFrameWithId:2 headers:headers last:NO];
    STAssertTrue([self waitForAnyCallbackOrFrame], nil);
    [self mockServerDataFrameWithId:2 length:1 last:YES];
    STAssertTrue([self waitForAnyCallbackOrFrame], nil);

    STAssertNotNil(_mockExtendedDelegate.lastPushResponse, nil);
    STAssertEquals(_mockExtendedDelegate.lastPushResponse.statusCode, (NSInteger)500, nil);
    STAssertNil(_mockPushResponseDataDelegate.lastWillCacheSuggestedResponse, nil);
    STAssertNotNil(_mockPushResponseDataDelegate.lastMetadata, nil);
    STAssertNil(_mockPushResponseDataDelegate.lastError, nil);

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/pushed"]];
    NSCachedURLResponse *response = [_mockExtendedDelegate.testSetsPushResponseCache cachedResponseForRequest:request];
    STAssertNil(response, nil);
}
#endif

@end
