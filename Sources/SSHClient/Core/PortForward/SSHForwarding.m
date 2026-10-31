#import "SSHForwarding.h"

@implementation SSHForwardChannel {
    LIBSSH2_CHANNEL *_channel;
}

- (nullable instancetype)initWithRawSession:(LIBSSH2_SESSION *)session
                                       host:(NSString *)host
                                       port:(UInt16)port {
    self = [super init];
    if (self) {
        const char *h = [host UTF8String];
        // 直接以本机为来源建立到目标 host:port 的 TCP 通道
        LIBSSH2_SESSION *s = (LIBSSH2_SESSION *)session;
        _channel = libssh2_channel_direct_tcpip_ex(s, h, (int)port, "127.0.0.1", 0);
        if (_channel == NULL) {
            return nil;
        }
    }
    return self;
}

- (NSData *)readData:(BOOL *)done error:(NSError **)error {
    if (_channel == NULL) { if (done) *done = YES; return nil; }
    char buf[16384];
    ssize_t n = libssh2_channel_read(_channel, buf, (size_t)sizeof(buf));
    if (n > 0) {
        if (done) *done = NO;
        return [NSData dataWithBytes:buf length:(NSUInteger)n];
    }
    if (n == LIBSSH2_ERROR_EAGAIN) {
        if (done) *done = NO;
        return [NSData data]; // 空数据表示暂无可读,继续轮询
    }
    if (n < 0) {
        if (done) *done = YES;
        if (error) *error = [NSError errorWithDomain:@"SSHForward" code:(int)n userInfo:nil];
        return nil;
    }
    // n == 0 → EOF
    if (done) *done = YES;
    return nil;
}

- (BOOL)writeData:(NSData *)data error:(NSError **)error {
    if (_channel == NULL) return NO;
    const char *p = (const char *)data.bytes;
    NSInteger total = data.length;
    while (total > 0) {
        ssize_t n = libssh2_channel_write(_channel, p, (size_t)total);
        if (n > 0) { p += n; total -= n; continue; }
        if (n == LIBSSH2_ERROR_EAGAIN) { continue; }
        if (error) *error = [NSError errorWithDomain:@"SSHForward" code:(int)n userInfo:nil];
        return NO;
    }
    return YES;
}

- (void)close {
    if (_channel) {
        libssh2_channel_close(_channel);
        libssh2_channel_free(_channel);
        _channel = NULL;
    }
}

@end
