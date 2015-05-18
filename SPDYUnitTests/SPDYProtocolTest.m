//
//  SPDYProtocolTest.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Kevin Goodier.
//

#import <SenTestingKit/SenTestingKit.h>
#import <Foundation/Foundation.h>
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYProtocol.h"
#import "SPDYTLSTrustEvaluator.h"

@interface SPDYProtocolTest : SenTestCase<SPDYTLSTrustEvaluator>
@end

@implementation SPDYProtocolTest
{
    NSString *_lastTLSTrustHost;
}

- (void)tearDown
{
    _lastTLSTrustHost = nil;
    [SPDYURLConnectionProtocol unregisterAllAliases];
    [SPDYURLConnectionProtocol unregisterAllOrigins];
    [SPDYProtocol setTLSTrustEvaluator:nil];
}

- (NSMutableURLRequest *)makeRequest:(NSString *)url
{
    return [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
}

#pragma mark SPDYTLSTrustEvaluator

- (BOOL)evaluateServerTrust:(SecTrustRef)trust forHost:(NSString *)host
{
    _lastTLSTrustHost = host;
    return NO;
}

#pragma mark Tests

- (void)testURLSessionCanInitTrue
{
    STAssertTrue([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com"]], nil);
    STAssertTrue([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com/foo"]], nil);
    STAssertTrue([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com:443/foo"]], nil);
    STAssertTrue([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com:8888/foo"]], nil);
    STAssertTrue([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"http://api.twitter.com/foo"]], nil);
}

- (void)testURLSessionCanInitFalse
{
    STAssertFalse([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"ftp://api.twitter.com"]], nil);
    STAssertFalse([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"://api.twitter.com"]], nil);
    STAssertFalse([SPDYURLSessionProtocol canInitWithRequest:[self makeRequest:@"api.twitter.com"]], nil);
}

- (void)testURLSessionWithBypassCanInitFalse
{
    NSMutableURLRequest *request = [self makeRequest:@"https://api.twitter.com"];
    request.SPDYBypass = YES;
    STAssertFalse([SPDYURLSessionProtocol canInitWithRequest:request], nil);
}

- (void)testURLConnectionCanInitTrue
{
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com"]], nil);
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com/foo"]], nil);
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com:443/foo"]], nil);
}

- (void)testURLConnectionCanInitFalse
{
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com:8888/foo"]], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"http://api.twitter.com"]], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://twitter.com"]], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://foo.api.twitter.com"]], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://twitter.com:80"]], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"http://api.twitter.com:443"]], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"://api.twitter.com"]], nil);
}

- (void)testURLConnectionWithBypassCanInitFalse
{
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    NSMutableURLRequest *request = [self makeRequest:@"https://api.twitter.com"];
    request.SPDYBypass = YES;
    STAssertFalse([SPDYURLSessionProtocol canInitWithRequest:request], nil);
}

- (void)testURLConnectionAliasCanInitTrue
{
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    [SPDYURLConnectionProtocol registerOrigin:@"https://1.2.3.4"];
    [SPDYProtocol registerAlias:@"https://alias.twitter.com" forOrigin:@"https://api.twitter.com"];
    [SPDYProtocol registerAlias:@"https://bare.twitter.com" forOrigin:@"https://1.2.3.4"];

    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com/foo"]], nil);
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://1.2.3.4/foo"]], nil);
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://alias.twitter.com/foo"]], nil);
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://bare.twitter.com/foo"]], nil);

    // TODO: Replace with unregisterAllAliases when available
    [SPDYProtocol unregisterAlias:@"https://alias.twitter.com"];
    [SPDYProtocol unregisterAlias:@"https://bare.twitter.com"];
}

- (void)testURLConnectionAliasToNoOriginCanInitFalse
{
    //[SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    [SPDYProtocol registerAlias:@"https://alias.twitter.com" forOrigin:@"https://api.twitter.com"];
    [SPDYProtocol registerAlias:@"https://bare.twitter.com" forOrigin:@"https://1.2.3.4"];

    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com/foo"]], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://1.2.3.4/foo"]], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://alias.twitter.com/foo"]], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://bare.twitter.com/foo"]], nil);

    // TODO: Replace with unregisterAllAliases when available
    [SPDYProtocol unregisterAlias:@"https://alias.twitter.com"];
    [SPDYProtocol unregisterAlias:@"https://bare.twitter.com"];
}

- (void)testURLConnectionBadAliasCanInitFalse
{
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    [SPDYProtocol registerAlias:@"ftp://alias.twitter.com" forOrigin:@"https://api.twitter.com"]; // bad alias

    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"ftp://alias.twitter.com/foo"]], nil);

    // TODO: Replace with unregisterAllAliases when available
    [SPDYProtocol unregisterAlias:@"ftp://alias.twitter.com"];
}

- (void)testURLConnectionCanInitTrueAfterWeirdOrigins
{
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com:8888"];
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com:8888/foo"]], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com/foo"]], nil);

    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com:8888/foo"]], nil);
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com/foo"]], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com:8889/foo"]], nil);

    [SPDYURLConnectionProtocol registerOrigin:@"https://www.twitter.com/foo"];
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://www.twitter.com/foo"]], nil);
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://www.twitter.com"]], nil);
}

- (void)testURLConnectionCanInitFalseAfterBadOrigins
{
    [SPDYURLConnectionProtocol registerOrigin:@"ftp://api.twitter.com"];
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com/foo"]], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"ftp://api.twitter.com/foo"]], nil);

    [SPDYURLConnectionProtocol registerOrigin:@"https://"];
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://"]], nil);
}

- (void)testURLConnectionCanInitFalseAfterUnregister
{
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    [SPDYURLConnectionProtocol registerOrigin:@"https://www.twitter.com"];
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com"]], nil);
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://www.twitter.com"]], nil);

    [SPDYURLConnectionProtocol unregisterOrigin:@"https://api.twitter.com"];
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://api.twitter.com"]], nil);
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://www.twitter.com"]], nil);

    [SPDYURLConnectionProtocol unregisterAllOrigins];
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:[self makeRequest:@"https://www.twitter.com"]], nil);
}

- (void)testTLSTrustEvaluatorReturnsYesWhenNotSet
{
    STAssertTrue([SPDYProtocol evaluateServerTrust:nil forHost:@"api.twitter.com"], nil);
}

- (void)testTLSTrustEvaluator
{
    [SPDYProtocol setTLSTrustEvaluator:self];
    STAssertFalse([SPDYProtocol evaluateServerTrust:nil forHost:@"api.twitter.com"], nil);
    STAssertEqualObjects(_lastTLSTrustHost, @"api.twitter.com", nil);
}

- (void)testTLSTrustEvaluatorWithCertificateAlias
{
    [SPDYProtocol setTLSTrustEvaluator:self];
    [SPDYURLConnectionProtocol registerOrigin:@"https://api.twitter.com"];
    [SPDYURLConnectionProtocol registerOrigin:@"https://1.2.3.4"];
    [SPDYProtocol registerAlias:@"https://alias.twitter.com" forOrigin:@"https://api.twitter.com"];
    [SPDYProtocol registerAlias:@"https://bare.twitter.com" forOrigin:@"https://1.2.3.4"];

    STAssertFalse([SPDYProtocol evaluateServerTrust:nil forHost:@"api.twitter.com"], nil);
    STAssertEqualObjects(_lastTLSTrustHost, @"api.twitter.com", nil);

    STAssertFalse([SPDYProtocol evaluateServerTrust:nil forHost:@"1.2.3.4"], nil);
    STAssertEqualObjects(_lastTLSTrustHost, @"bare.twitter.com", nil);

    // TODO: Replace with unregisterAllAliases when available
    [SPDYProtocol unregisterAlias:@"https://alias.twitter.com"];
    [SPDYProtocol unregisterAlias:@"https://bare.twitter.com"];
}

- (void)testSetAndGetConfiguration
{
    SPDYConfiguration *c1 = [SPDYConfiguration defaultConfiguration];
    c1.sessionPoolSize = 4;
    c1.sessionReceiveWindow = 2000;
    c1.streamReceiveWindow = 1000;
    c1.headerCompressionLevel = 5;
    c1.enableSettingsMinorVersion = NO;
    c1.tlsSettings = @{@"Key1":@"Value1"};
    c1.connectTimeout = 1.0;
    c1.enableTCPNoDelay = YES;

    [SPDYProtocol setConfiguration:c1];
    SPDYConfiguration *c2 = [SPDYProtocol currentConfiguration];

    STAssertEquals(c2.sessionPoolSize, (NSUInteger)4, nil);
    STAssertEquals(c2.sessionReceiveWindow, (NSUInteger)2000, nil);
    STAssertEquals(c2.streamReceiveWindow, (NSUInteger)1000, nil);
    STAssertEquals(c2.headerCompressionLevel, (NSUInteger)5, nil);
    STAssertEquals(c2.enableSettingsMinorVersion, NO, nil);
    STAssertEquals(c2.tlsSettings[@"Key1"], @"Value1", nil);
    STAssertEquals(c2.connectTimeout, 1.0, nil);
    STAssertEquals(c2.enableTCPNoDelay, YES, nil);

    // Reset
    [SPDYProtocol setConfiguration:[SPDYConfiguration defaultConfiguration]];
}

- (void)testRegisterOrigin
{
    NSURL *url1 = [NSURL URLWithString:@"https://mocked.com:443/bar.json"];
    NSURL *url2 = [NSURL URLWithString:@"https://mocked.com:8443/bar.json"];
    NSURL *url3 = [NSURL URLWithString:@"https://unmocked.com:443/bar.json"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url1];
    NSMutableURLRequest *request2 = [[NSMutableURLRequest alloc] initWithURL:url2];
    NSMutableURLRequest *request3 = [[NSMutableURLRequest alloc] initWithURL:url3];

    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:request1], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:request2], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:request3], nil);

    [SPDYURLConnectionProtocol registerOrigin:@"https://mocked.com:443"];
    [SPDYURLConnectionProtocol registerOrigin:@"https://mocked.com:8443"];
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:request1], nil);
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:request2], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:request3], nil);

    [SPDYURLConnectionProtocol unregisterOrigin:@"https://mocked.com:8443"];
    STAssertTrue([SPDYURLConnectionProtocol canInitWithRequest:request1], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:request2], nil);
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:request3], nil);

    [SPDYURLConnectionProtocol unregisterAllOrigins];
    [SPDYURLConnectionProtocol unregisterAllAliases];
    STAssertFalse([SPDYURLConnectionProtocol canInitWithRequest:request1], nil);
}

@end

