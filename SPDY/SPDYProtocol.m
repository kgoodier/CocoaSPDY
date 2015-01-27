//
//  SPDYProtocol.m
//  SPDY
//
//  Copyright (c) 2014 Twitter, Inc. All rights reserved.
//  Licensed under the Apache License v2.0
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Created by Michael Schore and Jeffrey Pinner.
//

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

// Enable diagnostic audit log only on-demand for developer builds
#ifdef DEBUG
#define VERBOSE_AUDIT_LOG 0
#endif

#import <arpa/inet.h>
#import "NSURLRequest+SPDYURLRequest.h"
#import "SPDYCanonicalRequest.h"
#import "SPDYCommonLogger.h"
#import "SPDYMetadata.h"
#import "SPDYOrigin.h"
#import "SPDYProtocol.h"
#import "SPDYSession.h"
#import "SPDYSessionManager.h"
#import "SPDYStream.h"
#import "SPDYTLSTrustEvaluator.h"

NSString *const SPDYStreamErrorDomain = @"SPDYStreamErrorDomain";
NSString *const SPDYSessionErrorDomain = @"SPDYSessionErrorDomain";
NSString *const SPDYCodecErrorDomain = @"SPDYCodecErrorDomain";
NSString *const SPDYSocketErrorDomain = @"SPDYSocketErrorDomain";
NSString *const SPDYOriginRegisteredNotification = @"SPDYOriginRegisteredNotification";
NSString *const SPDYOriginUnregisteredNotification = @"SPDYOriginUnregisteredNotification";
NSString *const SPDYMetadataVersionKey = @"x-spdy-version";
NSString *const SPDYMetadataSessionRemoteAddressKey = @"x-spdy-session-remote-address";
NSString *const SPDYMetadataSessionRemotePortKey = @"x-spdy-session-remote-port";
NSString *const SPDYMetadataSessionViaProxyKey = @"x-spdy-session-via-proxy";
NSString *const SPDYMetadataSessionLatencyKey = @"x-spdy-session-latency";
NSString *const SPDYMetadataStreamBlockedMsKey = @"x-spdy-stream-blocked-ms";
NSString *const SPDYMetadataStreamConnectedMsKey = @"x-spdy-stream-connected-ms";
NSString *const SPDYMetadataStreamIdKey = @"x-spdy-stream-id";
NSString *const SPDYMetadataStreamRxBytesKey = @"x-spdy-stream-rx-bytes";
NSString *const SPDYMetadataStreamTxBytesKey = @"x-spdy-stream-tx-bytes";

static char *const SPDYConfigQueue = "com.twitter.SPDYConfigQueue";

static NSMutableDictionary *aliases;
static NSMutableDictionary *certificates;
static dispatch_queue_t configQueue;
static dispatch_once_t initConfig;

@interface SPDYAssertionHandler : NSAssertionHandler
@property (nonatomic) BOOL abortOnFailure;
@end

@implementation SPDYAssertionHandler

- (instancetype)init
{
    self = [super init];
    if (self) {
        _abortOnFailure = YES;
    }
    return self;
}

- (void)handleFailureInMethod:(SEL)selector
                       object:(id)object
                         file:(NSString *)fileName
                   lineNumber:(NSInteger)line
                  description:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *reason = [NSString stringWithFormat:@"*** CocoaSPDY NSAssert failure '%@'\nin method '%@' for object %@ in %@#%zd\n%@", message, NSStringFromSelector(selector), object, fileName, line, [NSThread callStackSymbols]];
    SPDY_ERROR(@"%@", reason);
    [SPDYCommonLogger flush];
    if (_abortOnFailure) {
        abort();
    }
}

- (void)handleFailureInFunction:(NSString *)functionName
                           file:(NSString *)fileName
                     lineNumber:(NSInteger)line
                    description:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *reason = [NSString stringWithFormat:@"*** CocoaSPDY NSCAssert failure '%@'\nin function '%@' in %@#%zd\n%@", message, functionName, fileName, line, [NSThread callStackSymbols]];
    SPDY_ERROR(@"%@", reason);
    [SPDYCommonLogger flush];
    if (_abortOnFailure) {
        abort();
    }
}

@end

@implementation SPDYProtocol
{
    SPDYStream *_stream;
}

static SPDYConfiguration *currentConfiguration;
static id<SPDYTLSTrustEvaluator> trustEvaluator;

+ (void)initialize
{
    dispatch_once(&initConfig, ^{
        aliases = [[NSMutableDictionary alloc] init];
        certificates = [[NSMutableDictionary alloc] init];
        configQueue = dispatch_queue_create(SPDYConfigQueue, DISPATCH_QUEUE_CONCURRENT);
        currentConfiguration = [SPDYConfiguration defaultConfiguration];
    });

#ifdef DEBUG
    SPDY_WARNING(@"loaded DEBUG build of SPDY framework");
#endif
}

+ (SPDYConfiguration *)currentConfiguration
{
    __block SPDYConfiguration *configuration;
    dispatch_sync(configQueue, ^{
        configuration = [currentConfiguration copy];
    });
    return configuration;
}

+ (void)setConfiguration:(SPDYConfiguration *)configuration
{
    dispatch_barrier_async(configQueue, ^{
        currentConfiguration = [configuration copy];
    });
}

+ (void)setLogger:(id<SPDYLogger>)logger
{
    [SPDYCommonLogger setLogger:logger];
}

+ (id<SPDYLogger>)currentLogger
{
    return [SPDYCommonLogger currentLogger];
}

+ (void)setLoggerLevel:(SPDYLogLevel)level
{
    [SPDYCommonLogger setLoggerLevel:level];
}

+ (SPDYLogLevel)currentLoggerLevel
{
    return [SPDYCommonLogger currentLoggerLevel];
}

+ (void)setTLSTrustEvaluator:(id<SPDYTLSTrustEvaluator>)evaluator
{
    SPDY_INFO(@"register trust evaluator: %@", evaluator);
    dispatch_barrier_async(configQueue, ^{
        trustEvaluator = evaluator;
    });
}

+ (bool)evaluateServerTrust:(SecTrustRef)trust forHost:(NSString *)host {
    __block id<SPDYTLSTrustEvaluator> evaluator;
    __block NSString *namedHost;

    dispatch_sync(configQueue, ^{
        evaluator = trustEvaluator;
        namedHost = certificates[host];
    });

    if (evaluator == nil) return YES;
    if (namedHost != nil) host = namedHost;

    return [evaluator evaluateServerTrust:trust forHost:host];
}

+ (NSDictionary *)metadataForResponse:(NSURLResponse *)response
{
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    SPDYMetadata *metadata = [SPDYMetadata metadataForAssociatedDictionary:httpResponse.allHeaderFields];
    return [metadata dictionary];
}

+ (NSDictionary *)metadataForError:(NSError *)error
{
    SPDYMetadata *metadata = [SPDYMetadata metadataForAssociatedDictionary:error.userInfo];
    return [metadata dictionary];
}

+ (void)registerAlias:(NSString *)aliasString forOrigin:(NSString *)originString
{
    SPDYOrigin *alias = [[SPDYOrigin alloc] initWithString:aliasString error:nil];
    if (!alias) {
        SPDY_ERROR(@"invalid origin: %@", aliasString);
        return;
    }

    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:originString error:nil];
    if (!origin) {
        SPDY_ERROR(@"invalid origin: %@", originString);
        return;
    }

    SPDY_INFO(@"register alias: %@", aliasString);
    dispatch_barrier_async(configQueue, ^{
        aliases[alias] = origin;

        // Use the alias hostname for TLS validation if the aliased origin contains a bare IP address
        struct in_addr ipTest;
        if (inet_pton(AF_INET, [origin.host cStringUsingEncoding:NSUTF8StringEncoding], &ipTest)) {
            certificates[origin.host] = alias.host;
        }

        NSDictionary *info = @{ @"origin": originString, @"alias": aliasString };
        [[NSNotificationCenter defaultCenter] postNotificationName:SPDYOriginRegisteredNotification
                                                            object:nil
                                                          userInfo:info];
        SPDY_DEBUG(@"alias registered: %@", alias);
    });
}

+ (void)unregisterAlias:(NSString *)aliasString
{
    SPDYOrigin *alias = [[SPDYOrigin alloc] initWithString:aliasString error:nil];
    if (!alias) {
        SPDY_ERROR(@"invalid origin: %@", aliasString);
        return;
    }

    dispatch_barrier_async(configQueue, ^{
        SPDYOrigin *origin = aliases[alias];
        if (origin) {
            [aliases removeObjectForKey:alias];
            [certificates removeObjectForKey:origin.host];
            [[NSNotificationCenter defaultCenter] postNotificationName:SPDYOriginUnregisteredNotification
                                                                object:nil
                                                              userInfo:@{ @"alias": aliasString }];
            SPDY_DEBUG(@"alias unregistered: %@", alias);
        }
    });
}

+ (void)unregisterAllAliases
{
    dispatch_barrier_async(configQueue, ^{
        [aliases removeAllObjects];
        [certificates removeAllObjects];

        [[NSNotificationCenter defaultCenter] postNotificationName:SPDYOriginUnregisteredNotification
                                                            object:nil
                                                          userInfo:@{ @"alias": @"*"}];
        SPDY_DEBUG(@"unregistered all aliases");
    });
}

+ (SPDYOrigin *)originForAlias:(SPDYOrigin *)alias
{
    __block SPDYOrigin *origin;
    dispatch_sync(configQueue, ^{
        origin = aliases[alias];
    });
    return origin;
}

#pragma mark NSURLProtocol implementation

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    NSString *scheme = request.URL.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return NO;
    }

    return !request.SPDYBypass && ![request valueForHTTPHeaderField:@"x-spdy-bypass"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
    NSMutableURLRequest *canonicalRequest = SPDYCanonicalRequestForRequest(request);
    [SPDYProtocol setProperty:@(YES) forKey:@"x-spdy-is-canonical-request" inRequest:canonicalRequest];
    return canonicalRequest;
}

- (instancetype)initWithRequest:(NSURLRequest *)request cachedResponse:(NSCachedURLResponse *)cachedResponse client:(id <NSURLProtocolClient>)client
{
    // iOS 8 will call this using the 'request' returned from canonicalRequestForRequest. However,
    // iOS 7 passes the original (non-canonical) request. As SPDYCanonicalRequestForRequest is
    // somewhat heavyweight, we'll use a flag to detect non-canonical requests. Ensuring the
    // canonical form is used for processing is important for correctness.
    BOOL isCanonical = ([SPDYProtocol propertyForKey:@"x-spdy-is-canonical-request" inRequest:request] != nil);
    if (!isCanonical) {
        request = [SPDYProtocol canonicalRequestForRequest:request];
    }

    return [super initWithRequest:request cachedResponse:cachedResponse client:client];
}

- (void)startLoading
{
    // Add an assertion handler to this NSURL thread if one doesn't exist. Without it, assertions
    // will get swallowed on iOS. OSX seems to behave properly without it, but it's safer to
    // just always set this.
    NSMutableDictionary *currentThreadDictionary = [[NSThread currentThread] threadDictionary];
    if (currentThreadDictionary[NSAssertionHandlerKey] == nil) {
        currentThreadDictionary[NSAssertionHandlerKey] = [[SPDYAssertionHandler alloc] init];
    }

    // Only allow one startLoading call. iOS 8 using NSURLSession has exhibited different
    // behavior, by calling startLoading, then stopLoading, then startLoading, etc, over and
    // over. This happens asynchronously when using a NSURLSessionDataTaskDelegate after the
    // URLSession:dataTask:didReceiveResponse:completionHandler: callback.
    if (_stream) {
        SPDY_WARNING(@"start loading already called, ignoring %@", self.request.URL.absoluteString);
        return;
    }

    NSURLRequest *request = self.request;
    SPDY_INFO(@"start loading %@", request.URL.absoluteString);

    NSError *error;
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithURL:request.URL error:&error];
    if (!origin) {
        [self.client URLProtocol:self didFailWithError:error];
        return;
    }

    SPDYOrigin *aliasedOrigin = [SPDYProtocol originForAlias:origin];
    if (aliasedOrigin) {
        origin = aliasedOrigin;
    }

    SPDYSessionManager *manager = [SPDYSessionManager localManagerForOrigin:origin];
    _stream = [[SPDYStream alloc] initWithProtocol:self];
    [manager queueStream:_stream];
}

- (void)stopLoading
{
    SPDY_INFO(@"stop loading %@", self.request.URL.absoluteString);

#if VERBOSE_AUDIT_LOG

#define TIME_DIFF(startTime, stopTime) (NSInteger)(((stopTime) <= 0 || (startTime) <= 0) ? -1 : (1000 * ((stopTime) - (startTime))))
#define STREAMTIME_DIFF(stopTime) (NSInteger)((stopTime) <= 0 ? -1 : (1000 * ((stopTime) - metadata.timeStreamCreated)))

    SPDYMetadata *metadata = _stream.metadata;
    NSInteger duration = TIME_DIFF(metadata.timeStreamCreated, metadata.timeStreamClosed);
    NSInteger serverLatency = TIME_DIFF(metadata.timeStreamLastRequestData, metadata.timeStreamResponse);
    SPDY_INFO(@"STREAMMETA id %u connected %tu blocked %tu duration %zd serverLatency %zd latency %zd tx %tu rx %tu cellular %u host %@ url %@",
            metadata.streamId,
            metadata.connectedMs,
            metadata.blockedMs,
            duration,
            serverLatency,
            metadata.latencyMs,
            metadata.txBytes,
            metadata.rxBytes,
            (uint32_t)(metadata.cellular ? 1 : 0),
            metadata.hostAddress,
            self.request.URL.absoluteString);

    NSInteger createdAt = TIME_DIFF(metadata.timeSessionConnected, metadata.timeStreamStarted);
    NSInteger started = STREAMTIME_DIFF(metadata.timeStreamStarted);
    NSInteger lastRequestData = STREAMTIME_DIFF(metadata.timeStreamLastRequestData);
    NSInteger response = STREAMTIME_DIFF(metadata.timeStreamResponse);
    NSInteger firstData = STREAMTIME_DIFF(metadata.timeStreamFirstData);
    NSInteger closed = STREAMTIME_DIFF(metadata.timeStreamClosed);

    NSInteger requestDuration = (lastRequestData <= 0 || started <= 0) ? -1 : (lastRequestData - started);
    NSInteger dataDuration = (closed <= 0 || response <= 0) ? -1 : (closed - response);
    NSInteger txPerSecond = (requestDuration <= 0) ? -1 : (1000 * metadata.txBytes / requestDuration);
    NSInteger rxPerSecond = (dataDuration <= 0) ? -1 : (1000 * metadata.rxBytes / dataDuration);

    SPDY_INFO(@"STREAMTIME id %u createdAt %zd started %zd lastRequestData %zd response %zd firstData %zd closed %zd txps %zd rxps %zd tx %tu rx %tu url %@",
            metadata.streamId,
            createdAt,
            started,
            lastRequestData,
            response,
            firstData,
            closed,
            txPerSecond,
            rxPerSecond,
            metadata.txBytes,
            metadata.rxBytes,
            self.request.URL.absoluteString);

#undef TIME_DIFF
#undef STREAMTIME_DIFF

#endif

    if (_stream && !_stream.closed) {
        [_stream cancel];
    }
}

@end

#pragma mark NSURLSession implementation

@implementation SPDYURLSessionProtocol
@end


//__attribute__((constructor))
//static void registerSPDYURLConnectionProtocol() {
//    @autoreleasepool {
//        [NSURLProtocol registerClass:[SPDYURLConnectionProtocol class]];
//    }
//}

#pragma mark NSURLConnection implementation

@implementation SPDYURLConnectionProtocol
static dispatch_once_t initOrigins;
static NSMutableSet *origins;

+ (void)load
{
    // +[NSURLProtocol registerClass] is not threadsafe, so register before
    // requests start getting made.
    @autoreleasepool {
        [NSURLProtocol registerClass:self];
    }
}

+ (void)initialize
{
    dispatch_once(&initOrigins, ^{
        origins = [[NSMutableSet alloc] init];
    });
}

+ (void)registerOrigin:(NSString *)originString
{
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:originString error:nil];
    SPDY_INFO(@"register origin: %@", origin);
    if (!origin) {
        SPDY_ERROR(@"invalid origin: %@", originString);
        return;
    }

    dispatch_barrier_async(configQueue, ^{
        [origins addObject:origin];
        [[NSNotificationCenter defaultCenter] postNotificationName:SPDYOriginRegisteredNotification
                                                            object:nil
                                                          userInfo:@{ @"origin": originString }];
        SPDY_DEBUG(@"origin registered: %@", origin);
    });
}

+ (void)unregisterOrigin:(NSString *)originString
{
    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithString:originString error:nil];
    if (!origin) {
        SPDY_ERROR(@"invalid origin: %@", originString);
        return;
    }

    dispatch_barrier_async(configQueue, ^{
        if ([origins containsObject:origin]) {
            [origins removeObject:origin];
            [[NSNotificationCenter defaultCenter] postNotificationName:SPDYOriginUnregisteredNotification
                                                                object:nil
                                                              userInfo:@{ @"origin": originString }];
            SPDY_DEBUG(@"origin unregistered: %@", origin);
        }
    });
}

+ (void)unregisterAllOrigins
{
    dispatch_barrier_async(configQueue, ^{
        [origins removeAllObjects];
        [[NSNotificationCenter defaultCenter] postNotificationName:SPDYOriginUnregisteredNotification
                                                            object:nil
                                                          userInfo:@{ @"origin": @"*" }];
        SPDY_DEBUG(@"unregistered all origins");
    });
}

#pragma mark NSURLProtocol implementation

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
    if (![super canInitWithRequest:request]) {
        return NO;
    }

    SPDYOrigin *origin = [[SPDYOrigin alloc] initWithURL:request.URL error:nil];
    if (!origin) {
        return NO;
    }

    SPDYOrigin *aliasedOrigin = [SPDYProtocol originForAlias:origin];
    if (aliasedOrigin) {
        origin = aliasedOrigin;
    }

    __block bool originRegistered;
    dispatch_sync(configQueue, ^{
        originRegistered = [origins containsObject:origin];
    });
    return originRegistered;
}

@end

#pragma mark Configuration

@implementation SPDYConfiguration

static SPDYConfiguration *defaultConfiguration;

+ (void)initialize
{
    defaultConfiguration = [[SPDYConfiguration alloc] init];
    defaultConfiguration.headerCompressionLevel = 9;
    defaultConfiguration.sessionPoolSize = 1;
    defaultConfiguration.sessionReceiveWindow = 10485760;
    defaultConfiguration.streamReceiveWindow = 10485760;
    defaultConfiguration.enableSettingsMinorVersion = NO;
    defaultConfiguration.tlsSettings = @{ /* use Apple default TLS settings */ };
    defaultConfiguration.connectTimeout = 60.0;
    defaultConfiguration.enableTCPNoDelay = NO;
    defaultConfiguration.enableProxy = YES;
    defaultConfiguration.proxyHost = nil;
    defaultConfiguration.proxyPort = 0;
}

+ (SPDYConfiguration *)defaultConfiguration
{
    return [defaultConfiguration copy];
}

- (id)copyWithZone:(NSZone *)zone
{
    SPDYConfiguration *copy = [[SPDYConfiguration allocWithZone:zone] init];
    copy.headerCompressionLevel = _headerCompressionLevel;
    copy.sessionPoolSize = _sessionPoolSize;
    copy.sessionReceiveWindow = _sessionReceiveWindow;
    copy.streamReceiveWindow = _streamReceiveWindow;
    copy.enableSettingsMinorVersion = _enableSettingsMinorVersion;
    copy.tlsSettings = _tlsSettings;
    copy.connectTimeout = _connectTimeout;
    copy.enableTCPNoDelay = _enableTCPNoDelay;
    copy.enableProxy = _enableProxy;
    copy.proxyHost = _proxyHost;
    copy.proxyPort = _proxyPort;
    return copy;
}

@end
