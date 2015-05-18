//
//  SPDYURLRequestTest.m
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
#import "SPDYCanonicalRequest.h"
#import "SPDYProtocol.h"

@interface SPDYURLRequestTest : SenTestCase
@end

@implementation SPDYURLRequestTest

- (NSDictionary *)headersForUrl:(NSString *)urlString
{
    NSURL *url = [[NSURL alloc] initWithString:urlString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    request = SPDYCanonicalRequestForRequest(request);
    return [request allSPDYHeaderFields];
}

- (NSDictionary *)headersForRequest:(NSMutableURLRequest *)request
{
    request = SPDYCanonicalRequestForRequest(request);
    return [request allSPDYHeaderFields];
}

- (NSMutableURLRequest *)buildRequestForUrl:(NSString *)urlString method:(NSString *)httpMethod
{
    NSURL *url = [[NSURL alloc] initWithString:urlString];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request setHTTPMethod:httpMethod];
    return request;
}

- (void)testAllSPDYHeaderFields
{
    // Test basic mainline case with a single custom multi-value header.
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request addValue:@"TestValue1" forHTTPHeaderField:@"TestHeader"];
    [request addValue:@"TestValue2" forHTTPHeaderField:@"TestHeader"];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@":method"], @"GET", nil);
    STAssertEqualObjects(headers[@":path"], @"/test/path", nil);
    STAssertEqualObjects(headers[@":version"], @"HTTP/1.1", nil);
    STAssertEqualObjects(headers[@":host"], @"example.com", nil);
    STAssertEqualObjects(headers[@":scheme"], @"http", nil);
    STAssertEqualObjects(headers[@"testheader"], @"TestValue1,TestValue2", nil);
    STAssertNil(headers[@"content-type"], nil);  // not present by default for GET
}

- (void)testReservedHeaderOverrides
{
    // These are internal SPDY headers that may be overridden.
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request setValue:@"HEAD" forHTTPHeaderField:@"method"];
    [request setValue:@"/test/path/override" forHTTPHeaderField:@"path"];
    [request setValue:@"HTTP/1.0" forHTTPHeaderField:@"version"];
    [request setValue:@"override.example.com" forHTTPHeaderField:@"host"];
    [request setValue:@"ftp" forHTTPHeaderField:@"scheme"];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertEqualObjects(headers[@":method"], @"HEAD", nil);
    STAssertEqualObjects(headers[@":path"], @"/test/path/override", nil);
    STAssertEqualObjects(headers[@":version"], @"HTTP/1.0", nil);
    STAssertEqualObjects(headers[@":host"], @"override.example.com", nil);
    STAssertEqualObjects(headers[@":scheme"], @"ftp", nil);
}

- (void)testInvalidHeaderKeys
{
    // These headers are not allowed by SPDY
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request setValue:@"none" forHTTPHeaderField:@"Connection"];
    [request setValue:@"none" forHTTPHeaderField:@"Keep-Alive"];
    [request setValue:@"none" forHTTPHeaderField:@"Proxy-Connection"];
    [request setValue:@"none" forHTTPHeaderField:@"Transfer-Encoding"];

    NSDictionary *headers = [request allSPDYHeaderFields];
    STAssertNil(headers[@"connection"], nil);
    STAssertNil(headers[@"keep-alive"], nil);
    STAssertNil(headers[@"proxy-connection"], nil);
    STAssertNil(headers[@"transfer-encoding"], nil);
}

- (void)testContentTypeHeaderDefaultForPost
{
    // Ensure SPDY adds a default content-type when request is a POST with body.
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"POST"];
    [request setSPDYBodyFile:@"bodyfile.json"];

    NSDictionary *headers = [self headersForRequest:request];
    STAssertEqualObjects(headers[@":method"], @"POST", nil);
    STAssertEqualObjects(headers[@"content-type"], @"application/x-www-form-urlencoded", nil);
}

- (void)testContentTypeHeaderCustomForPost
{
    // Ensure we can also override the default content-type.
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"POST"];
    [request setSPDYBodyFile:@"bodyfile.json"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSDictionary *headers = [self headersForRequest:request];
    STAssertEqualObjects(headers[@":method"], @"POST", nil);
    STAssertEqualObjects(headers[@"content-type"], @"application/json", nil);
}

- (void)testContentLengthHeaderDefaultForPostWithHTTPBody
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"POST"];
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:data];

    NSDictionary *headers = [self headersForRequest:request];
    STAssertEqualObjects(headers[@"content-length"], [@(data.length) stringValue], nil);
}

- (void)testContentLengthHeaderDefaultForPostWithInvalidSPDYBodyFile
{
    // An invalid body file will result in a size of 0
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"POST"];
    [request setSPDYBodyFile:@"doesnotexist.json"];

    NSDictionary *headers = [self headersForRequest:request];
    STAssertEqualObjects(headers[@"content-length"], @"0", nil);
}

- (void)testContentLengthHeaderDefaultForPostWithSPDYBodyStream
{
    // No default for input streams
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"POST"];
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    NSInputStream *dataStream = [NSInputStream inputStreamWithData:data];
    [request setSPDYBodyStream:dataStream];

    NSDictionary *headers = [self headersForRequest:request];
    STAssertEqualObjects(headers[@"content-length"], nil, nil);
}

- (void)testContentLengthHeaderCustomForPostWithSPDYBodyStream
{
    // No default for input streams
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"POST"];
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    NSInputStream *dataStream = [NSInputStream inputStreamWithData:data];
    [request setSPDYBodyStream:dataStream];
    [request setValue:@"12" forHTTPHeaderField:@"Content-Length"];

    NSDictionary *headers = [self headersForRequest:request];
    STAssertEqualObjects(headers[@"content-length"], @"12", nil);
}

- (void)testContentLengthHeaderCustomForPostWithHTTPBody
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"POST"];
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:data];
    [request setValue:@"1" forHTTPHeaderField:@"Content-Length"];

    NSDictionary *headers = [self headersForRequest:request];
    STAssertEqualObjects(headers[@"content-length"], @"1", nil);
}

- (void)testContentLengthHeaderDefaultForPutWithHTTPBody
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"PUT"];
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:data];

    NSDictionary *headers = [self headersForRequest:request];
    STAssertEqualObjects(headers[@"content-length"], [@(data.length) stringValue], nil);
}

- (void)testContentLengthHeaderDefaultForGet
{
    // Unusual but not explicitly disallowed
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"GET"];

    NSDictionary *headers = [self headersForRequest:request];
    STAssertEqualObjects(headers[@"content-length"], nil, nil);
}

- (void)testContentLengthHeaderDefaultForGetWithHTTPBody
{
    // Unusual but not explicitly disallowed
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"GET"];
    NSData *data = [@"Hello World" dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:data];

    NSDictionary *headers = [self headersForRequest:request];
    STAssertEqualObjects(headers[@"content-length"], [@(data.length) stringValue], nil);
}

- (void)testAcceptEncodingHeaderDefault
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"GET"];

    NSDictionary *headers = [self headersForRequest:request];
    STAssertEqualObjects(headers[@"accept-encoding"], @"gzip, deflate", nil);
}

- (void)testAcceptEncodingHeaderCustom
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/test/path" method:@"GET"];
    [request setValue:@"bogus" forHTTPHeaderField:@"Accept-Encoding"];

    NSDictionary *headers = [self headersForRequest:request];
    STAssertEqualObjects(headers[@"accept-encoding"], @"bogus", nil);
}

- (void)testPathHeaderWithQueryString
{
    NSDictionary *headers = [self headersForUrl:@"http://example.com/test/path?param1=value1&param2=value2"];
    STAssertEqualObjects(headers[@":path"], @"/test/path?param1=value1&param2=value2", nil);
}

- (void)testPathHeaderWithQueryStringAndFragment
{
    NSDictionary *headers = [self headersForUrl:@"http://example.com/test/path?param1=value1&param2=value2#fraggles"];
    STAssertEqualObjects(headers[@":path"], @"/test/path?param1=value1&param2=value2#fraggles", nil);
}

- (void)testPathHeaderWithQueryStringAndFragmentInMixedCase
{
    NSDictionary *headers = [self headersForUrl:@"http://example.com/Test/Path?Param1=Value1#Fraggles"];
    STAssertEqualObjects(headers[@":path"], @"/Test/Path?Param1=Value1#Fraggles", nil);
}

- (void)testPathHeaderWithURLEncodedPath
{
    NSDictionary *headers = [self headersForUrl:@"http://example.com/test/path/%E9%9F%B3%E6%A5%BD.json"];
    STAssertEqualObjects(headers[@":path"], @"/test/path/%E9%9F%B3%E6%A5%BD.json", nil);
}

- (void)testPathHeaderWithURLEncodedPathReservedChars
{
    // Besides non-ASCII characters, paths may contain any valid URL character except "?#[]".
    // Test path: /gen?#[]/sub!$&'()*+,;=/unres-._~
    // Note that NSURL chokes on non-encoded ";" in path, so we'll test it separately.
    NSDictionary *headers = [self headersForUrl:@"http://example.com/gen%3F%23%5B%5D/sub!$&'()*+,=/unres-._~?p1=v1"];
    STAssertEqualObjects(headers[@":path"], @"/gen%3F%23%5B%5D/sub!$&'()*+,=/unres-._~?p1=v1", nil);

    // Test semicolon separately
    headers = [self headersForUrl:@"http://example.com/semi%3B"];
    STAssertEqualObjects(headers[@":path"], @"/semi;", nil);
}

- (void)testPathHeaderWithDoubleURLEncodedPath
{
    // Ensure double encoding "#!", "%23%21", are preserved
    NSDictionary *headers = [self headersForUrl:@"http://example.com/double%2523%2521/tail"];
    STAssertEqualObjects(headers[@":path"], @"/double%2523%2521/tail", nil);

    // Ensure double encoding non-ASCII characters are preserved
    headers = [self headersForUrl:@"http://example.com/doublenonascii%25E9%259F%25B3%25E6%25A5%25BD"];
    STAssertEqualObjects(headers[@":path"], @"/doublenonascii%25E9%259F%25B3%25E6%25A5%25BD", nil);
}

- (void)testPathHeaderWithURLEncodedQueryStringAndFragment
{
    NSDictionary *headers = [self headersForUrl:@"http://example.com/test/path?param1=%E9%9F%B3%E6%A5%BD#fraggles%20rule"];
    STAssertEqualObjects(headers[@":path"], @"/test/path?param1=%E9%9F%B3%E6%A5%BD#fraggles%20rule", nil);
}

- (void)testPathHeaderEmpty
{
    NSDictionary *headers = [self headersForUrl:@"http://example.com"];
    STAssertEqualObjects(headers[@":path"], @"/", nil);
}

- (void)testSPDYProperties
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    NSInputStream *stream = [[NSInputStream alloc] initWithData:[NSData new]];
    NSURLSession *urlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

    request.SPDYPriority = 1;
    request.SPDYDeferrableInterval = 3.95;
    request.SPDYBypass = YES;
    request.SPDYBodyStream = stream;
    request.SPDYBodyFile = @"Bodyfile.json";
    request.SPDYURLSession = urlSession;

    STAssertEquals(request.SPDYPriority, (NSUInteger)1, nil);
    STAssertEquals(request.SPDYDeferrableInterval, (double)3.95, nil);
    STAssertEquals(request.SPDYBypass, (BOOL)YES, nil);
    STAssertEquals(request.SPDYBodyStream, stream, nil);
    STAssertEquals(request.SPDYBodyFile, @"Bodyfile.json", nil);
    STAssertEquals(request.SPDYURLSession, urlSession, nil);

    NSMutableURLRequest *mutableCopy = [request mutableCopy];

    STAssertEquals(mutableCopy.SPDYPriority, (NSUInteger)1, nil);
    STAssertEquals(mutableCopy.SPDYDeferrableInterval, (double)3.95, nil);
    STAssertEquals(mutableCopy.SPDYBypass, (BOOL)YES, nil);
    STAssertEquals(mutableCopy.SPDYBodyStream, stream, nil);
    STAssertEquals(mutableCopy.SPDYBodyFile, @"Bodyfile.json", nil);
    STAssertEquals(mutableCopy.SPDYURLSession, urlSession, nil);

    NSURLRequest *immutableCopy = [request copy];

    STAssertEquals(immutableCopy.SPDYPriority, (NSUInteger)1, nil);
    STAssertEquals(immutableCopy.SPDYDeferrableInterval, (double)3.95, nil);
    STAssertEquals(immutableCopy.SPDYBypass, (BOOL)TRUE, nil);
    STAssertEquals(immutableCopy.SPDYBodyStream, stream, nil);
    STAssertEquals(immutableCopy.SPDYBodyFile, @"Bodyfile.json", nil);
    STAssertEquals(immutableCopy.SPDYURLSession, urlSession, nil);
}

- (void)testRequestCopyDoesRetainProperties
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];

    NSMutableURLRequest __weak *weakRequest;
    NSInputStream __weak *weakStream;
    NSString __weak *weakBodyFile;
    NSURLSession __weak *weakURLSession;
    NSURLRequest *immutableCopy;

    @autoreleasepool {
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
        request.SPDYBodyStream = [[NSInputStream alloc] initWithData:[NSData new]];
        request.SPDYBodyFile = [NSString stringWithFormat:@"Bodyfile.json"];
        request.SPDYURLSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];

        weakRequest = request;
        weakStream = request.SPDYBodyStream;
        weakBodyFile = request.SPDYBodyFile;
        weakURLSession = request.SPDYURLSession;

       immutableCopy = [request copy];
    }

    STAssertNil(weakRequest, nil);  // totally gone
    STAssertNotNil(weakStream, nil);  // still around
    STAssertNotNil(weakBodyFile, nil);  // still around
    STAssertNotNil(weakURLSession, nil);  // still around

    STAssertEquals(immutableCopy.SPDYBodyStream, weakStream, nil);
    STAssertEquals(immutableCopy.SPDYBodyFile, weakBodyFile, nil);
    STAssertEquals(immutableCopy.SPDYURLSession, weakURLSession, nil);
}

- (void)testRequestCacheEqualityDoesIgnoreProperties
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];

    // Build request with headers & properties
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url];
    [request addValue:@"Bar" forHTTPHeaderField:@"Foo"];
    request.SPDYPriority = 2;
    request.SPDYURLSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    request.SPDYBodyFile = @"Bodyfile.json";

    // Build response
    NSDictionary *responseHeaders = @{@"Content-Length": @"1000", @"Cache-Control": @"max-age=3600", @"TestHeader": @"TestValue"};
    NSMutableData *responseData = [[NSMutableData alloc] initWithCapacity:1000];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:responseHeaders];
    NSCachedURLResponse *cachedResponse = [[NSCachedURLResponse alloc] initWithResponse:response data:responseData];

    // Cache it
    NSURLCache *cache = [[NSURLCache alloc] initWithMemoryCapacity:512000 diskCapacity:10000000 diskPath:@"testcache"];
    [cache storeCachedResponse:cachedResponse forRequest:request];

    // New request, no properties or headers
    NSMutableURLRequest *newRequest = [[NSMutableURLRequest alloc] initWithURL:url];
    NSCachedURLResponse *newCachedResponse = [cache cachedResponseForRequest:newRequest];

    STAssertNotNil(newCachedResponse, nil);
    STAssertNil(newRequest.SPDYURLSession, nil);
    STAssertEqualObjects(((NSHTTPURLResponse *)newCachedResponse.response).allHeaderFields[@"TestHeader"], @"TestValue", nil);
}

#define EQUALITYTEST_SETUP() \
NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"]; \
NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url]; \
NSMutableURLRequest *request2 = [[NSMutableURLRequest alloc] initWithURL:url]; \

- (void)testEqualityForIdenticalIsYes
{
    EQUALITYTEST_SETUP();

    request1.HTTPMethod = @"GET";
    request2.HTTPMethod = @"GET";
    request1.SPDYPriority = 2;
    request2.SPDYPriority = 2;
    [request1 setValue:@"Value1" forHTTPHeaderField:@"Header1"];
    [request2 setValue:@"Value1" forHTTPHeaderField:@"Header1"];

    STAssertTrue([request1 isEqual:request2], nil);
    NSMutableSet *set = [[NSMutableSet alloc] init];
    [set addObject:request1];
    STAssertTrue([set containsObject:request2], nil);
}

- (void)testEqualityForHTTPBodySameDataIsYes
{
    EQUALITYTEST_SETUP();

    NSMutableData *data = [[NSMutableData alloc] initWithLength:8];
    request1.HTTPBody = data;
    request2.HTTPBody = data;

    STAssertTrue([request1 isEqual:request2], nil);
}

- (void)testEqualityForHTTPBodyNilDifferenceIsYes
{
    EQUALITYTEST_SETUP();
    NSMutableData *data = [[NSMutableData alloc] initWithLength:8];
    request1.HTTPBody = data;

    STAssertTrue([request1 isEqual:request2], nil);
}

- (void)testEqualityForHTTPBodyDifferentDataIsYes
{
    EQUALITYTEST_SETUP();
    NSMutableData *data = [[NSMutableData alloc] initWithLength:8];
    NSMutableData *data2 = [[NSMutableData alloc] initWithLength:8];
    request1.HTTPBody = data;
    request2.HTTPBody = data2;

    STAssertTrue([request1 isEqual:request2], nil);
}

- (void)testEqualityForHeaderNameDifferentCaseIsYes
{
    EQUALITYTEST_SETUP();
    [request1 setValue:@"Value1" forHTTPHeaderField:@"Header1"];
    [request2 setValue:@"Value1" forHTTPHeaderField:@"header1"];

    STAssertTrue([request1 isEqual:request2], nil);
}

- (void)testEqualityForTimeoutIntervalDifferentIsYes
{
    EQUALITYTEST_SETUP();
    request1.timeoutInterval = 5;
    request2.timeoutInterval = 6;

    STAssertTrue([request1 isEqual:request2], nil);
}

- (void)testEqualityForHTTPMethodDifferentIsNo
{
    EQUALITYTEST_SETUP();

    request1.HTTPMethod = @"GET";
    request2.HTTPMethod = @"POST";

    STAssertFalse([request1 isEqual:request2], nil);

    NSMutableSet *set = [[NSMutableSet alloc] init];
    [set addObject:request1];
    STAssertFalse([set containsObject:request2], nil);
}

- (void)testEqualityForSPDYPriorityDifferentIsNo
{
    EQUALITYTEST_SETUP();

    request1.HTTPMethod = @"GET";
    request2.HTTPMethod = @"GET";
    request1.SPDYPriority = 2;
    request2.SPDYPriority = 3;

    STAssertFalse([request1 isEqual:request2], nil);
}

- (void)testEqualityForURLPathDifferentIsNo
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSURL *url2 = [[NSURL alloc] initWithString:@"http://example.com/test/path2"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url];
    NSMutableURLRequest *request2 = [[NSMutableURLRequest alloc] initWithURL:url2];

    STAssertFalse([request1 isEqual:request2], nil);
}

- (void)testEqualityForURLPathCaseDifferentIsNo
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSURL *url2 = [[NSURL alloc] initWithString:@"http://example.com/test/PATH"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url];
    NSMutableURLRequest *request2 = [[NSMutableURLRequest alloc] initWithURL:url2];

    STAssertFalse([request1 isEqual:request2], nil);
}

- (void)testEqualityForURLHostCaseDifferentIsNo
{
    NSURL *url = [[NSURL alloc] initWithString:@"http://example.com/test/path"];
    NSURL *url2 = [[NSURL alloc] initWithString:@"http://Example.com/test/path"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url];
    NSMutableURLRequest *request2 = [[NSMutableURLRequest alloc] initWithURL:url2];

    STAssertFalse([request1 isEqual:request2], nil);
}

- (void)testEqualityForHeaderNameDifferentIsNo
{
    EQUALITYTEST_SETUP();

    [request1 setValue:@"Value1" forHTTPHeaderField:@"Header1"];
    [request2 setValue:@"Value1" forHTTPHeaderField:@"Header2"];

    STAssertFalse([request1 isEqual:request2], nil);
}

- (void)testEqualityForHeaderValueDifferentIsNo
{
    EQUALITYTEST_SETUP();
    [request1 setValue:@"Value1" forHTTPHeaderField:@"Header1"];
    [request2 setValue:@"Value2" forHTTPHeaderField:@"Header1"];

    STAssertFalse([request1 isEqual:request2], nil);
}

- (void)testEqualityForHeaderValueDifferentCaseIsNo
{
    EQUALITYTEST_SETUP();
    [request1 setValue:@"Value1" forHTTPHeaderField:@"Header1"];
    [request2 setValue:@"value1" forHTTPHeaderField:@"Header1"];

    STAssertFalse([request1 isEqual:request2], nil);
}

- (void)testEqualityForCachePolicyDifferentIsNo
{
    EQUALITYTEST_SETUP();
    request1.cachePolicy = NSURLCacheStorageAllowed;
    request2.cachePolicy = NSURLCacheStorageNotAllowed;

    STAssertFalse([request1 isEqual:request2], nil);
}

- (void)testEqualityForHTTPShouldHandleCookiesDifferentIsNo
{
    EQUALITYTEST_SETUP();
    request1.HTTPShouldHandleCookies = YES;
    request2.HTTPShouldHandleCookies = NO;
    
    STAssertFalse([request1 isEqual:request2], nil);
}

- (void)testCanonicalRequestAddsUserAgent
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/" method:@"GET"];
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    NSString *userAgent = [canonicalRequest valueForHTTPHeaderField:@"User-Agent"];
    STAssertNotNil(userAgent, nil);
    STAssertTrue([userAgent rangeOfString:@"CFNetwork/"].location > 0, nil);
    STAssertTrue([userAgent rangeOfString:@"Darwin/"].location > 0, nil);
}

- (void)testCanonicalRequestDoesNotOverwriteUserAgent
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/" method:@"GET"];
    [request setValue:@"Foobar/2" forHTTPHeaderField:@"User-Agent"];
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    NSString *userAgent = [canonicalRequest valueForHTTPHeaderField:@"User-Agent"];
    STAssertEqualObjects(userAgent, @"Foobar/2", nil);
}

- (void)testCanonicalRequestDoesNotOverwriteUserAgentWhenEmpty
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com/" method:@"GET"];
    [request setValue:@"" forHTTPHeaderField:@"User-Agent"];
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    NSString *userAgent = [canonicalRequest valueForHTTPHeaderField:@"User-Agent"];
    STAssertEqualObjects(userAgent, @"", nil);
}

- (void)testCanonicalRequestAddsHost
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://:80/foo" method:@"GET"];
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    STAssertEqualObjects(canonicalRequest.URL.absoluteString, @"http://localhost:80/foo", nil);
}

- (void)testCanonicalRequestAddsEmptyPath
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com" method:@"GET"];
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    STAssertEqualObjects(canonicalRequest.URL.absoluteString, @"http://example.com/", nil);
}

- (void)testCanonicalRequestAddsEmptyPathWithPort
{
    NSMutableURLRequest *request = [self buildRequestForUrl:@"http://example.com:80" method:@"GET"];
    NSURLRequest *canonicalRequest = [SPDYProtocol canonicalRequestForRequest:request];

    STAssertEqualObjects(canonicalRequest.URL.absoluteString, @"http://example.com:80/", nil);
}

- (void)testCanonicalRequestLowercaseHost
{
    NSURL *url1 = [NSURL URLWithString:@"https://Mocked.com/bar.json"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url1];
    NSURLRequest *canonicalRequest1 = [SPDYProtocol canonicalRequestForRequest:request1];
    STAssertEqualObjects(canonicalRequest1.URL.absoluteString, @"https://mocked.com/bar.json", nil);
}

- (void)testCanonicalRequestPathMissing
{
    NSURL *url1 = [NSURL URLWithString:@"https://mocked.com"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url1];
    NSURLRequest *canonicalRequest1 = [SPDYProtocol canonicalRequestForRequest:request1];
    STAssertEqualObjects(canonicalRequest1.URL.absoluteString, @"https://mocked.com/", nil);
}

- (void)testCanonicalRequestSchemeBad
{
    NSURL *url1 = [NSURL URLWithString:@"https:mocked.com"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url1];
    NSURLRequest *canonicalRequest1 = [SPDYProtocol canonicalRequestForRequest:request1];
    STAssertEqualObjects(canonicalRequest1.URL.absoluteString, @"https://mocked.com/", nil);
}

- (void)testCanonicalRequestMissingHost
{
    NSURL *url1 = [NSURL URLWithString:@"https://:443/bar.json"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url1];
    NSURLRequest *canonicalRequest1 = [SPDYProtocol canonicalRequestForRequest:request1];
    STAssertEqualObjects(canonicalRequest1.URL.absoluteString, @"https://localhost:443/bar.json", nil);
}

- (void)testCanonicalRequestHeaders
{
    NSURL *url1 = [NSURL URLWithString:@"https://mocked.com/bar.json"];
    NSMutableURLRequest *request1 = [[NSMutableURLRequest alloc] initWithURL:url1];
    request1.HTTPMethod = @"POST";
    request1.SPDYBodyFile = @"bodyfile.txt";
    NSURLRequest *canonicalRequest1 = [SPDYProtocol canonicalRequestForRequest:request1];
    STAssertEqualObjects(canonicalRequest1.URL.absoluteString, @"https://mocked.com/bar.json", nil);
    STAssertEqualObjects(canonicalRequest1.allHTTPHeaderFields[@"Content-Type"], @"application/x-www-form-urlencoded", nil);
    STAssertEqualObjects(canonicalRequest1.allHTTPHeaderFields[@"Accept"], @"*/*", nil);
    STAssertEqualObjects(canonicalRequest1.allHTTPHeaderFields[@"Accept-Encoding"], @"gzip, deflate", nil);
    STAssertEqualObjects(canonicalRequest1.allHTTPHeaderFields[@"Accept-Language"], @"en-us", nil);  // suspect
}

@end
