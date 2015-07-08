//
//  SPDYSessionTest.m
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
#import <Foundation/Foundation.h>
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYFrame.h"
#import "SPDYMockFrameEncoderDelegate.h"
#import "SPDYMockFrameDecoderDelegate.h"
#import "SPDYMockSessionTestBase.h"
#import "SPDYMockURLProtocolClient.h"
#import "SPDYOrigin.h"
#import "SPDYSession.h"
#import "SPDYSocket+SPDYSocketMock.h"
#import "SPDYStopwatch.h"
#import "SPDYStream.h"

@interface SPDYSessionTest : SPDYMockSessionTestBase
@end

@implementation SPDYSessionTest

- (void)testCloseSessionWithMultipleStreams
{
    // Exchange initial SYN_STREAM and SYN_REPLY for 2 streams then close the session. This
    // causes a GOAWAY and RST_STREAMs to be sent, via the "_closeWithStatus" method. That's
    // what we're testing.
    [self mockSynStreamAndReplyWithId:1 last:NO];
    [self mockSynStreamAndReplyWithId:3 last:YES];
    [self mockSynStreamAndReplyWithId:5 last:NO];
    [_session close];

    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)3, nil);
    STAssertTrue([_mockDecoderDelegate.framesReceived[0] isKindOfClass:[SPDYGoAwayFrame class]], nil);
    STAssertTrue([_mockDecoderDelegate.framesReceived[1] isKindOfClass:[SPDYRstStreamFrame class]], nil);
    STAssertTrue([_mockDecoderDelegate.framesReceived[2] isKindOfClass:[SPDYRstStreamFrame class]], nil);
    STAssertEquals(((SPDYGoAwayFrame *)_mockDecoderDelegate.framesReceived[0]).lastGoodStreamId, (SPDYStreamId)0, nil);
    STAssertEquals(((SPDYGoAwayFrame *)_mockDecoderDelegate.framesReceived[0]).statusCode, SPDY_SESSION_OK, nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[1]).streamId, (SPDYStreamId)1, nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[1]).statusCode, SPDY_STREAM_CANCEL, nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[2]).streamId, (SPDYStreamId)5, nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.framesReceived[2]).statusCode, SPDY_STREAM_CANCEL, nil);

    // Was connection:didFailWithError called?
    STAssertTrue(_mockURLProtocolClient.calledDidFailWithError, nil);
    STAssertNotNil(_mockURLProtocolClient.lastError, nil);

    // Was metadata populated for the error?
    SPDYMetadata *metadata = [SPDYProtocol metadataForError:_mockURLProtocolClient.lastError];
    STAssertEqualObjects(metadata.version, @"3.1", nil);
    STAssertEquals(metadata.streamId, (NSUInteger)5, nil);
}

- (void)testReceivedMetadataForSingleShortRequest
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    [self mockSynStreamAndReplyWithId:1 last:YES];

    STAssertNil(_mockDecoderDelegate.lastFrame, nil);
    STAssertTrue(_mockURLProtocolClient.calledDidFinishLoading, nil);
    STAssertNotNil(_mockURLProtocolClient.lastResponse, nil);

    SPDYMetadata *metadata = [SPDYProtocol metadataForResponse:_mockURLProtocolClient.lastResponse];
    STAssertEqualObjects(metadata.version, @"3.1", nil);
    STAssertEquals(metadata.streamId, (NSUInteger)1, nil);
    STAssertTrue(metadata.rxBytes > 0, nil);
    STAssertTrue(metadata.txBytes > 0, nil);
    STAssertEquals(metadata.rxBodyBytes, (NSUInteger)0, nil);
    STAssertEquals(metadata.txBodyBytes, (NSUInteger)0, nil);
}

- (void)testReceivedMetadataForSingleShortRequestWithBody
{
    // Exchange initial SYN_STREAM and SYN_REPLY
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://mocked/init"]];
    _URLRequest.HTTPMethod = @"POST";
    _URLRequest.HTTPBody = [[NSMutableData alloc] initWithLength:1000];
    [self mockSynStreamAndReplyWithId:1 last:NO];
    [self mockServerDataWithId:1 data:[[NSMutableData alloc] initWithLength:2000] last:YES];

    STAssertNil(_mockDecoderDelegate.lastFrame, nil);
    STAssertTrue(_mockURLProtocolClient.calledDidFinishLoading, nil);
    STAssertNotNil(_mockURLProtocolClient.lastResponse, nil);

    SPDYMetadata *metadata = [SPDYProtocol metadataForResponse:_mockURLProtocolClient.lastResponse];
    STAssertEqualObjects(metadata.version, @"3.1", nil);
    STAssertEquals(metadata.streamId, (NSUInteger)1, nil);
    STAssertTrue(metadata.rxBytes > 2008, nil);
    STAssertTrue(metadata.txBytes > 1008, nil);
    STAssertEquals(metadata.rxBodyBytes, (NSUInteger)2008, nil);
    STAssertEquals(metadata.txBodyBytes, (NSUInteger)1008, nil);
}

- (void)testReceivedStreamTimingsMetadataForSingleShortRequest
{
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol] pushStreamManager:nil];
    [_session openStream:stream];
    STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYSynStreamFrame class]], nil);
    [_mockDecoderDelegate clear];

    [SPDYStopwatch sleep:1.0];
    [self mockServerSynReplyWithId:1 last:NO];

    [SPDYStopwatch sleep:1.0];
    NSMutableData *data = [NSMutableData dataWithLength:1];
    [self mockServerDataWithId:1 data:data last:NO];
    [SPDYStopwatch sleep:1.0];
    [self mockServerDataWithId:1 data:data last:YES];

    // These fields aren't yet exposed externally; when they are, this code should change.
    SPDYMetadata *metadata = stream.metadata;
    STAssertEqualObjects(metadata.version, @"3.1", nil);
    STAssertTrue(metadata.timeSessionConnected > 0, nil);
    STAssertTrue(metadata.timeStreamCreated >= metadata.timeSessionConnected, nil);
    STAssertTrue(metadata.timeStreamRequestStarted >= metadata.timeStreamCreated, nil);
    STAssertTrue(metadata.timeStreamRequestLastHeader >= metadata.timeStreamRequestStarted, nil);
    STAssertTrue(metadata.timeStreamRequestFirstData == 0, nil);
    STAssertTrue(metadata.timeStreamRequestLastData == 0, nil);
    STAssertTrue(metadata.timeStreamRequestEnded >= metadata.timeStreamRequestStarted, nil);

    STAssertTrue(metadata.timeStreamResponseStarted >= metadata.timeStreamRequestEnded + 1.0, nil);
    STAssertTrue(metadata.timeStreamResponseLastHeader >= metadata.timeStreamResponseStarted, nil);
    STAssertTrue(metadata.timeStreamResponseFirstData >= metadata.timeStreamResponseLastHeader + 1.0, nil);
    STAssertTrue(metadata.timeStreamResponseLastData >= metadata.timeStreamResponseFirstData + 1.0, nil);
    STAssertTrue(metadata.timeStreamResponseEnded >= metadata.timeStreamResponseStarted + 2.0, nil);
    STAssertTrue(metadata.timeStreamClosed >= metadata.timeStreamResponseEnded, nil);
}

- (void)testReceiveGOAWAYAfterStreamsClosedDoesCloseSession
{
    [self mockSynStreamAndReplyWithId:1 last:YES];
    [self mockSynStreamAndReplyWithId:3 last:YES];
    [self mockSynStreamAndReplyWithId:5 last:YES];
    [self mockServerGoAwayWithLastGoodId:5 statusCode:SPDY_SESSION_OK];
    STAssertEquals(_session.load, (NSUInteger)0, nil);
    STAssertFalse(_session.isOpen, nil);
}

- (void)testReceiveGOAWAYWithOpenStreamsDoesNotCloseSession
{
    [self mockSynStreamAndReplyWithId:1 last:YES];
    [self mockSynStreamAndReplyWithId:3 last:NO];
    [self mockSynStreamAndReplyWithId:5 last:NO];
    [self mockServerGoAwayWithLastGoodId:5 statusCode:SPDY_SESSION_OK];
    STAssertEquals(_session.load, (NSUInteger)2, nil);
    STAssertFalse(_session.isOpen, nil);

    // Now close the 2 in-flight streams. Session should close.
    [self mockServerDataFrameWithId:3 length:0 last:YES];
    STAssertEquals(_session.load, (NSUInteger)1, nil);

    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)0, nil);
    [self mockServerDataFrameWithId:5 length:0 last:YES];
    STAssertEquals(_session.load, (NSUInteger)0, nil);
    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)1, nil);
    STAssertTrue([_mockDecoderDelegate.framesReceived[0] isKindOfClass:[SPDYGoAwayFrame class]], nil);
}

- (void)testReceiveGOAWAYWithInFlightStreamsDoesCloseStreams
{
    [self mockSynStreamAndReplyWithId:1 last:YES];
    [self mockSynStreamAndReplyWithId:3 last:NO];
    [self mockSynStreamAndReplyWithId:5 last:NO];
    [self mockServerGoAwayWithLastGoodId:1 statusCode:SPDY_SESSION_OK];
    STAssertEquals(_session.load, (NSUInteger)0, nil);
    STAssertFalse(_session.isOpen, nil);
}

- (void)testReceiveGOAWAYWithInFlightStreamDoesResetStreams
{
    [self mockSynStreamAndReplyWithId:1 last:YES];

    // Send two SYN_STREAMs only, no reply
    [_session openStream:[[SPDYStream alloc] initWithProtocol:[self createProtocol] pushStreamManager:nil]];
    STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYSynStreamFrame class]], nil);
    [_mockDecoderDelegate clear];

    [_session openStream:[[SPDYStream alloc] initWithProtocol:[self createProtocol] pushStreamManager:nil]];
    STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYSynStreamFrame class]], nil);
    [_mockDecoderDelegate clear];

    [self mockServerGoAwayWithLastGoodId:1 statusCode:SPDY_SESSION_OK];
    STAssertEquals(_session.load, (NSUInteger)0, nil);
    STAssertFalse(_session.isOpen, nil);

    // TODO: verify these streams were sent back to the session manager
}

- (void)testSendDATABufferRemainsValidAfterRequestIsDone
{
    NSMutableData * __weak weakData = nil;
    @autoreleasepool {
        @autoreleasepool {
            NSMutableData *data = [NSMutableData dataWithLength:16];
            ((uint8_t *)data.bytes)[0] = 1;
            weakData = data;
            NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/init"]];
            urlRequest.HTTPBody = data;
            SPDYProtocol *protocolRequest = [[SPDYProtocol alloc] initWithRequest:urlRequest cachedResponse:nil client:_mockURLProtocolClient];

            // Copy of:
            // [self mockSynStreamAndReplyWithId:1 last:NO];

            // Prepare the synReplyFrame. The SYN_STREAM will use stream-id 1 since it is the first
            // request sent by the client. We can't control that without mocking, so we have to hard-code
            // the SYN_REPLY stream id.
            SPDYSynReplyFrame *synReplyFrame = [[SPDYSynReplyFrame alloc] init];
            synReplyFrame.headers = @{@":version" : @"3.1", @":status" : @"200"};
            synReplyFrame.streamId = 1;
            synReplyFrame.last = YES;

            // 1.) Issue a HTTP request towards the server, this will send the SYN_STREAM request and wait
            // for the SYN_REPLY. It will use stream-id of 1 since it's the first request.
            [_session openStream:[[SPDYStream alloc] initWithProtocol:protocolRequest pushStreamManager:nil]];
            STAssertTrue([_mockDecoderDelegate.framesReceived[0] isKindOfClass:[SPDYSynStreamFrame class]], nil);
            STAssertTrue([_mockDecoderDelegate.framesReceived[1] isKindOfClass:[SPDYDataFrame class]], nil);
            STAssertTrue(((SPDYDataFrame *)_mockDecoderDelegate.framesReceived[1]).last, nil);
            STAssertNotNil(socketMock_lastWriteOp, nil);
            STAssertEquals(socketMock_lastWriteOp->_buffer.length, data.length, nil);
            [_mockDecoderDelegate clear];

            // 1 active stream
            STAssertEquals(_session.load, (NSUInteger)1, nil);

            // 2.) Simulate a server Tx stream SYN reply
            STAssertTrue([_testEncoder encodeSynReplyFrame:synReplyFrame error:nil] > 0, nil);
            [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];
            [_testEncoderDelegate clear];

            // 2.1) We should not expect any protocol errors to be issued from the client.
            STAssertNil(_mockDecoderDelegate.lastFrame, nil);

            // Ensure completion callback (our custom one) was called to verify request is actually
            // finished.
            STAssertTrue(_mockURLProtocolClient.calledDidFinishLoading, nil);

            // At this point, socketMock_lastWriteOp is holding a pointer to our data. That simulates
            // what happens deep inside SPDYSocket if, for instance, other operations are queued
            // in front of ours or the full buffer cannot be written to the stream just yet.
            // Eventually the operation will be released, but we want to test the case where it
            // is still in progress and the stream goes away.

            // No more active streams
            STAssertEquals(_session.load, (NSUInteger)0, nil);

            // Need to test that the write op's buffered data isn't our data pointer, since it is
            // about to go away. I'd like to do that without crashing the unit test, so we'll
            // mutate the original buffer and verify our hypothesis after releasing the request.
            // Lots of sanity checks here on out.
            STAssertTrue(((uint8_t *)socketMock_lastWriteOp->_buffer.bytes)[0] == 1, nil);
            ((uint8_t *)data.bytes)[0] = 2;
            STAssertTrue(((uint8_t *)weakData.bytes)[0] == 2, nil);
        }  // <<< this releases the request

        STAssertNotNil(socketMock_lastWriteOp, nil);  // sanity
        if (weakData == nil) {
            // Buffer expected to have been copied since original is released. Data should be
            // original non-mutated value.
            STAssertTrue(((uint8_t *)socketMock_lastWriteOp->_buffer.bytes)[0] == 1,
                    @"socket still references original buffer which has been released");
        } else {
            // Buffer expected to have been retained by the socket since the original has not been
            // released yet. It would be dumb to retain it but still make a data copy, so let's
            // verify the socket's buffer still points to the original which was mutated.
            STAssertTrue(((uint8_t *)socketMock_lastWriteOp->_buffer.bytes)[0] == 2,
                    @"socket should still point to the original buffer which has not been released yet");
        }

        // Dequeue
        socketMock_lastWriteOp = nil;
    }  // <<< this releases the "queued" write

    // And verify original buffer is now gone
    STAssertNil(weakData, nil);
}

- (void)testCancelStreamDoesSendResetAndCloseStream
{
    SPDYStream * __weak weakStream = nil;
    @autoreleasepool {
        SPDYStream *stream = [self mockSynStreamAndReplyWithId:1 last:NO];
        weakStream = stream;
        [stream cancel];

        STAssertNotNil(_mockDecoderDelegate.lastFrame, nil);
        STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]], nil);
        STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).statusCode, SPDY_STREAM_CANCEL, nil);
        STAssertTrue(_session.isOpen, nil);
        STAssertEquals(_session.load, (NSUInteger)0, nil);
    }
    // Ensure stream was released as well
    STAssertNil(weakStream, nil);
}

- (void)testReceiveDATABeforeSYNREPLYDoesResetAndCloseStream
{
    NSMutableData *data = [NSMutableData dataWithLength:1];

    // Send a SYN_STREAM, no reply
    [_session openStream:[[SPDYStream alloc] initWithProtocol:[self createProtocol] pushStreamManager:nil]];
    STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYSynStreamFrame class]], nil);
    [_mockDecoderDelegate clear];

    // Reply with DATA
    [self mockServerDataWithId:1 data:data last:NO];

    // Ensure RST_STREAM was sent
    STAssertNotNil(_mockDecoderDelegate.lastFrame, nil);
    STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]], nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).statusCode, SPDY_STREAM_PROTOCOL_ERROR, nil);
    STAssertTrue(_session.isOpen, nil);
    STAssertEquals(_session.load, (NSUInteger)0, nil);
}

- (void)testReceiveMultipleSYNREPLYDoesResetAndCloseStream
{
    [self mockSynStreamAndReplyWithId:1 last:NO];
    [self mockServerSynReplyWithId:1 last:NO];

    // Ensure RST_STREAM was sent
    STAssertNotNil(_mockDecoderDelegate.lastFrame, nil);
    STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYRstStreamFrame class]], nil);
    STAssertEquals(((SPDYRstStreamFrame *)_mockDecoderDelegate.lastFrame).statusCode, SPDY_STREAM_STREAM_IN_USE, nil);
    STAssertTrue(_session.isOpen, nil);
    STAssertEquals(_session.load, (NSUInteger)0, nil);
}

- (void)testInitWithTcpNodelayDoesSendPING
{
    NSError *error = nil;
    SPDYConfiguration *configuration = [SPDYConfiguration defaultConfiguration];
    configuration.enableTCPNoDelay = YES;
    _session = [[SPDYSession alloc] initWithOrigin:_origin
                                          delegate:nil
                                     configuration:configuration
                                          cellular:NO
                                             error:&error];

    STAssertFalse(_session.isEstablished, nil);
    STAssertTrue([_mockDecoderDelegate.lastFrame isKindOfClass:[SPDYPingFrame class]], nil);
    STAssertEquals(((SPDYPingFrame *)_mockDecoderDelegate.lastFrame).pingId, (SPDYPingId)1, nil);

    // Reply with response
    SPDYPingFrame *pingFrame = [[SPDYPingFrame alloc] init];
    pingFrame.pingId = 1;  // server-initiated is even

    STAssertTrue([_testEncoder encodePingFrame:pingFrame] > 0, nil);
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];
    [_testEncoderDelegate clear];
    STAssertTrue(_session.isEstablished, nil);
}

- (void)testServerPING
{
    SPDYPingFrame *pingFrame = [[SPDYPingFrame alloc] init];
    pingFrame.pingId = 2;  // server-initiated is even

    STAssertTrue([_testEncoder encodePingFrame:pingFrame] > 0, nil);
    [self makeSessionReadData:_testEncoderDelegate.lastEncodedData];
    [_testEncoderDelegate clear];

    // Verify ping response sent
    STAssertEquals(_mockDecoderDelegate.frameCount, (NSUInteger)1, nil);
    STAssertTrue([_mockDecoderDelegate.framesReceived[0] isKindOfClass:[SPDYPingFrame class]], nil);
    STAssertEquals(((SPDYPingFrame *)_mockDecoderDelegate.framesReceived[0]).pingId, (SPDYPingId)2, nil);
}

- (void)testMergeHeadersWithLocationAnd200DoesRedirect
{
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://mocked/init"]];
    _URLRequest.SPDYPriority = 3;
    _URLRequest.HTTPMethod = @"POST";
    _URLRequest.SPDYBodyFile = @"bodyfile.txt";
    _URLRequest.SPDYDeferrableInterval = 1.0;
    [_URLRequest setValue:@"50" forHTTPHeaderField:@"content-length"];

    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol] pushStreamManager:nil];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"https", @":host":@"mocked", @":path":@"/init",
            @":status":@"200", @":version":@"http/1.1", @"Header1":@"Value1",
            @"location":@"/newpath"};
    NSURL *redirectUrl = [NSURL URLWithString:@"https://mocked/newpath"];

    [stream mergeHeaders:headers];
    [stream didReceiveResponse];
    STAssertTrue(_mockURLProtocolClient.calledWasRedirectedToRequest, nil);

    NSURLRequest *redirectRequest = _mockURLProtocolClient.lastRedirectedRequest;
    STAssertEqualObjects(redirectRequest.URL.absoluteString, redirectUrl.absoluteString, nil);
    STAssertEqualObjects(redirectRequest.URL, redirectUrl, nil);
    STAssertEquals(redirectRequest.SPDYPriority, (NSUInteger)3, nil);
    STAssertEqualObjects(redirectRequest.HTTPMethod, @"POST", nil);
    STAssertEqualObjects(redirectRequest.SPDYBodyFile, @"bodyfile.txt", nil);
    STAssertEquals(redirectRequest.SPDYDeferrableInterval, 1.0, nil);
    STAssertEqualObjects(redirectRequest.allSPDYHeaderFields[@"content-length"], @"50", nil);
    STAssertNotNil(redirectRequest.allSPDYHeaderFields[@"content-type"], nil);

    STAssertEqualObjects(((NSHTTPURLResponse *)_mockURLProtocolClient.lastRedirectResponse).allHeaderFields[@"Header1"], @"Value1", nil);
}

- (void)testMergeHeadersWithLocationAnd302DoesRedirectToGET
{
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://mocked/init"]];
    _URLRequest.HTTPMethod = @"POST";
    _URLRequest.SPDYBodyFile = @"bodyfile.txt";
    [_URLRequest setValue:@"50" forHTTPHeaderField:@"content-length"];

    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol] pushStreamManager:nil];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"http", @":host":@"mocked", @":path":@"/init",
            @":status":@"302", @":version":@"http/1.1", @"Header1":@"Value1",
            @"location":@"https://mocked2/newpath"};
    NSURL *redirectUrl = [NSURL URLWithString:@"https://mocked2/newpath"];

    [stream mergeHeaders:headers];
    [stream didReceiveResponse];
    STAssertTrue(_mockURLProtocolClient.calledWasRedirectedToRequest, nil);

    NSURLRequest *redirectRequest = _mockURLProtocolClient.lastRedirectedRequest;
    STAssertEqualObjects(redirectRequest.URL.absoluteString, redirectUrl.absoluteString, nil);
    STAssertEqualObjects(redirectRequest.URL, redirectUrl, nil);
    STAssertEqualObjects(redirectRequest.HTTPMethod, @"GET", @"expect GET after 302");  // 302 generally means GET
    STAssertNil(redirectRequest.SPDYBodyFile, nil);
    STAssertNil(redirectRequest.HTTPBodyStream, nil);
    STAssertNil(redirectRequest.allSPDYHeaderFields[@"content-length"], nil);
    STAssertNil(redirectRequest.allSPDYHeaderFields[@"content-type"], nil);
}

- (void)testMergeHeadersWithLocationAnd303DoesRedirectToGET
{
    NSInputStream *inputStream = [NSInputStream inputStreamWithFileAtPath:@"foo"];
    _URLRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://mocked/init"]];
    _URLRequest.HTTPMethod = @"POST";
    _URLRequest.HTTPBodyStream = inputStream;  // test stream this time
    SPDYStream *stream = [[SPDYStream alloc] initWithProtocol:[self createProtocol] pushStreamManager:nil];
    [stream startWithStreamId:1 sendWindowSize:1024 receiveWindowSize:1024];

    NSDictionary *headers = @{@":scheme":@"https", @":host":@"mocked", @":path":@"/init",
            @":status":@"303", @":version":@"http/1.1", @"Header1":@"Value1",
            @"location":@"/newpath?param=value&foo=1"};
    NSURL *redirectUrl = [NSURL URLWithString:@"https://mocked/newpath?param=value&foo=1"];

    [stream mergeHeaders:headers];
    [stream didReceiveResponse];
    STAssertTrue(_mockURLProtocolClient.calledWasRedirectedToRequest, nil);

    NSURLRequest *redirectRequest = _mockURLProtocolClient.lastRedirectedRequest;
    STAssertEqualObjects(redirectRequest.URL.absoluteString, redirectUrl.absoluteString, nil);
    STAssertEqualObjects(redirectRequest.URL, redirectUrl, nil);
    STAssertEqualObjects(redirectRequest.HTTPMethod, @"GET", @"expect GET after 303");  // 303 means GET
    STAssertNil(redirectRequest.SPDYBodyFile, nil);
    STAssertNil(redirectRequest.HTTPBodyStream, nil);
    STAssertNil(redirectRequest.allSPDYHeaderFields[@"content-length"], nil);
    STAssertNil(redirectRequest.allSPDYHeaderFields[@"content-type"], nil);
}

- (void)testNetworkChangesWhenSocketConnectsDoesUpdateActiveStreamMetadata
{
    // Queue stream to session (set to WIFI)
    SPDYStream *stream = [self mockSynStreamAndReplyWithId:1 last:NO];
    STAssertTrue(_session.isOpen, nil);
    STAssertFalse(stream.closed, nil);

    SPDYMetadata *metadata = [stream metadata];
    STAssertFalse(metadata.cellular, nil);

    // Then force socket connection on different network.
    [_session.socket setCellular:YES];
    [_session.socket performDelegateCall_socketDidConnectToHost:_origin.host port:_origin.port];

    STAssertTrue(_session.isOpen, nil);
    STAssertFalse(stream.closed, nil);

    metadata = [stream metadata];
    STAssertTrue(metadata.cellular, nil);
}

@end

