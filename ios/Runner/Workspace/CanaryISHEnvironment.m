#import "CanaryISHEnvironment.h"

#include <string.h>

const NSUInteger CanaryISHEnvironmentMaxBytes = 128 * 1024;

NSData *CanaryISHEncodeEnvironment(NSDictionary<NSString *, NSString *> *environment,
                                 CanaryISHEnvironmentError *error) {
    *error = CanaryISHEnvironmentErrorNone;
    NSMutableData *block = [NSMutableData data];
    const char nul = '\0';
    for (NSString *key in environment) {
        if (key.length == 0 || [key containsString:@"="]) {
            *error = CanaryISHEnvironmentErrorInvalidEntry;
            return nil;
        }
        NSString *entry = [NSString stringWithFormat:@"%@=%@", key, environment[key]];
        NSData *bytes = [entry dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
        if (bytes == nil || memchr(bytes.bytes, '\0', bytes.length) != NULL) {
            *error = CanaryISHEnvironmentErrorInvalidEntry;
            return nil;
        }
        // Reserve both this entry's terminator and the final empty entry.
        if (block.length + 2 > CanaryISHEnvironmentMaxBytes ||
            bytes.length > CanaryISHEnvironmentMaxBytes - block.length - 2) {
            *error = CanaryISHEnvironmentErrorTooLarge;
            return nil;
        }
        [block appendData:bytes];
        [block appendBytes:&nul length:1];
    }
    [block appendBytes:&nul length:1];
    return block;
}

NSString *CanaryISHEnvironmentErrorMessage(CanaryISHEnvironmentError error) {
    if (error == CanaryISHEnvironmentErrorTooLarge) {
        return @"Environment variables exceed the iOS sandbox limit of 128 KiB (UTF-8). Reduce their total size and try again.";
    }
    return @"Invalid environment variable name or value.";
}
