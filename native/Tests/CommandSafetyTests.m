#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>

// Inert harness: the supplied script must collect command strings, never send
// events to Terminal. The Python driver instruments the real packaged source.
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        NSError *error = nil;
        NSString *source = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]
            encoding:NSUTF8StringEncoding error:&error];
        NSData *input = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];
        NSArray<NSString *> *paths = input == nil ? nil : [NSJSONSerialization JSONObjectWithData:input options:0 error:&error];
        if (source == nil || paths == nil || [source containsString:@"com.apple.Terminal"] || [source containsString:@"do script"]) {
            fprintf(stderr, "Invalid or non-inert test source.\n");
            return 3;
        }
        NSAppleEventDescriptor *arguments = [NSAppleEventDescriptor listDescriptor];
        NSInteger index = 1;
        for (NSString *path in paths) {
            NSString *token = [[path dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
            [arguments insertDescriptor:[NSAppleEventDescriptor descriptorWithString:token] atIndex:index++];
        }
        NSAppleEventDescriptor *handlerArguments = [NSAppleEventDescriptor listDescriptor];
        [handlerArguments insertDescriptor:arguments atIndex:1];
        NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:kASAppleScriptSuite
            eventID:kASSubroutineEvent targetDescriptor:nil
            returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
        [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:@"openfolders"] forKeyword:keyASSubroutineName];
        [event setParamDescriptor:handlerArguments forKeyword:keyDirectObject];
        NSDictionary *scriptError = nil;
        NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
        NSAppleEventDescriptor *result = [script executeAppleEvent:event error:&scriptError];
        if (result == nil) {
            fprintf(stderr, "AppleScript test failed: %s\n", [[scriptError description] UTF8String]);
            return 4;
        }
        NSMutableArray<NSString *> *commands = [NSMutableArray array];
        for (NSInteger item = 1; item <= result.numberOfItems; item++) {
            NSString *command = [result descriptorAtIndex:item].stringValue;
            if (command == nil) return 5;
            [commands addObject:command];
        }
        NSData *output = [NSJSONSerialization dataWithJSONObject:commands options:0 error:&error];
        if (output == nil) return 6;
        [[NSFileHandle fileHandleWithStandardOutput] writeData:output];
    }
    return 0;
}
