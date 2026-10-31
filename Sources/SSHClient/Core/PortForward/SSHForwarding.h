#import <Foundation/Foundation.h>
#import <libssh2.h>

NS_ASSUME_NONNULL_BEGIN

/// 基于 libssh2 direct-tcpip 的转发通道(经 NMSSH 暴露的 rawSession 建立)。
/// NMSSH 本身未提供端口转发,这里补齐该能力。
@interface SSHForwardChannel : NSObject

- (nullable instancetype)initWithRawSession:(void *)session
                                       host:(NSString *)host
                                       port:(UInt16)port;

/// 阻塞读取;done=YES 表示对端已关闭。EAGAIN 时返回空 Data 且 done=NO。
- (NSData *)readData:(BOOL *)done error:(NSError **)error;

- (BOOL)writeData:(NSData *)data error:(NSError **)error;

- (void)close;

@end

NS_ASSUME_NONNULL_END
