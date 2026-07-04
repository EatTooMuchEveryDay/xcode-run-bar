#import "XcodeBridge.h"
#import "../Generated/Xcode.h"

NSErrorDomain const XBErrorDomain = @"io.github.rui.xcode-run-bar";

@interface XBEventDelegate : NSObject <SBApplicationDelegate>
@property (nonatomic, strong, nullable) NSError *lastError;
@end

@implementation XBEventDelegate

- (id)eventDidFail:(const AppleEvent *)event withError:(NSError *)error {
    NSLog(@"xcode-run-bar: AppleEvent failed: domain=%@ code=%ld description=%@", error.domain, (long)error.code, error.localizedDescription);
    self.lastError = error;
    return nil;
}

@end

@interface XBWorkspaceSnapshot ()

@property (nonatomic, strong, readonly) XcodeWorkspaceDocument *document;
@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSString *path;
@property (nonatomic, copy, readwrite) NSString *schemeName;
@property (nonatomic, copy, readwrite) NSString *destinationName;
@property (nonatomic, copy, readwrite) NSDate *modificationDate;

- (instancetype)initWithDocument:(XcodeWorkspaceDocument *)document
                            name:(NSString *)name
                            path:(NSString *)path
                      schemeName:(NSString *)schemeName
                  destinationName:(NSString *)destinationName
                 modificationDate:(NSDate *)modificationDate;

@end

@implementation XBWorkspaceSnapshot

- (instancetype)initWithDocument:(XcodeWorkspaceDocument *)document
                            name:(NSString *)name
                            path:(NSString *)path
                      schemeName:(NSString *)schemeName
                  destinationName:(NSString *)destinationName
                 modificationDate:(NSDate *)modificationDate {
    self = [super init];
    if (self) {
        _document = document;
        _name = [name copy];
        _path = [path copy];
        _schemeName = [schemeName copy];
        _destinationName = [destinationName copy];
        _modificationDate = [modificationDate copy];
    }
    return self;
}

@end

@interface XBActionResult ()

@property (nonatomic, strong, readonly) XcodeSchemeActionResult *result;

- (instancetype)initWithResult:(XcodeSchemeActionResult *)result;

@end

@implementation XBActionResult

- (instancetype)initWithResult:(XcodeSchemeActionResult *)result {
    self = [super init];
    if (self) {
        _result = result;
    }
    return self;
}

@end

@interface XcodeBridge ()
@property (nonatomic, strong) XBEventDelegate *eventDelegate;
@end

@implementation XcodeBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _eventDelegate = [XBEventDelegate new];
    }
    return self;
}

- (BOOL)isXcodeRunning {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dt.Xcode"].count > 0;
}

- (NSArray<XBWorkspaceSnapshot *> *)fetchWorkspacesAndReturnError:(NSError **)error {
    NSLog(@"xcode-run-bar: fetchWorkspaces started; xcodeRunning=%@", self.isXcodeRunning ? @"YES" : @"NO");

    if (!self.isXcodeRunning) {
        [self setError:error code:XBErrorCodeXcodeNotRunning underlying:nil];
        return nil;
    }

    __block NSArray<XBWorkspaceSnapshot *> *snapshots = nil;
    BOOL ok = [self perform:error block:^{
        XcodeApplication *app = [self xcodeApplication];
        NSArray<XcodeWorkspaceDocument *> *documents = [[app workspaceDocuments] get] ?: @[];
        NSLog(@"xcode-run-bar: workspaceDocuments count=%lu", (unsigned long)documents.count);
        NSMutableArray<XBWorkspaceSnapshot *> *items = [NSMutableArray array];

        for (XcodeWorkspaceDocument *document in documents) {
            NSString *path = [self stringValue:[self optionalValue:@"workspace.path" block:^id{
                return document.path;
            }]];
            if (path.length == 0) {
                NSURL *fileURL = [self optionalValue:@"workspace.file" block:^id{
                    return document.file;
                }];
                path = [self pathValue:fileURL];
            }
            if (path.length == 0) {
                NSLog(@"xcode-run-bar: skipped workspace without path");
                continue;
            }

            NSString *name = [self stringValue:[self optionalValue:@"workspace.name" block:^id{
                return document.name;
            }]] ?: path.lastPathComponent.stringByDeletingPathExtension;
            NSString *schemeName = [self schemeNameForDocument:document] ?: @"No scheme";
            NSString *destinationName = [self destinationNameForDocument:document] ?: @"No destination";
            NSDate *modificationDate = [self modificationDateForPath:path];

            NSLog(@"xcode-run-bar: workspace path=%@ name=%@ scheme=%@ destination=%@", path, name, schemeName, destinationName);

            XBWorkspaceSnapshot *snapshot = [[XBWorkspaceSnapshot alloc] initWithDocument:document
                                                                                     name:name
                                                                                     path:path
                                                                               schemeName:schemeName
                                                                           destinationName:destinationName
                                                                          modificationDate:modificationDate];
            [items addObject:snapshot];
        }

        snapshots = items;
        NSLog(@"xcode-run-bar: fetchWorkspaces finished; snapshots count=%lu", (unsigned long)snapshots.count);
    }];

    NSLog(@"xcode-run-bar: fetchWorkspaces result=%@", ok ? @"OK" : @"FAILED");
    return ok ? snapshots : nil;
}

- (XBActionResult *)runWorkspace:(XBWorkspaceSnapshot *)workspace error:(NSError **)error {
    __block XBActionResult *action = nil;
    BOOL ok = [self perform:error block:^{
        XcodeSchemeActionResult *result = [workspace.document runWithCommandLineArguments:nil withEnvironmentVariables:nil];
        if (result) {
            action = [[XBActionResult alloc] initWithResult:result];
        }
    }];

    if (!ok || !action) {
        if (ok) {
            [self setError:error code:XBErrorCodeCommandFailed underlying:nil];
        }
        return nil;
    }

    return action;
}

- (BOOL)stopWorkspace:(XBWorkspaceSnapshot *)workspace error:(NSError **)error {
    return [self perform:error block:^{
        [workspace.document stop];
    }];
}

- (BOOL)focusWorkspace:(XBWorkspaceSnapshot *)workspace error:(NSError **)error {
    return [self perform:error block:^{
        XcodeApplication *app = [self xcodeApplication];
        [app activate];
        app.activeWorkspaceDocument = workspace.document;

        NSArray<XcodeWindow *> *windows = [[app windows] get] ?: @[];
        for (XcodeWindow *window in windows) {
            NSString *windowPath = [self pathValue:[self optionalValue:@"window.document.path" block:^id{
                return window.document.path;
            }]];
            if ([windowPath isEqualToString:workspace.path]) {
                window.miniaturized = NO;
                window.visible = YES;
                window.index = 1;
                break;
            }
        }
    }];
}

- (NSNumber *)completedValueForAction:(XBActionResult *)result error:(NSError **)error {
    __block BOOL completed = NO;
    BOOL ok = [self perform:error block:^{
        completed = result.result.completed;
    }];
    return ok ? @(completed) : nil;
}

- (NSNumber *)statusValueForAction:(XBActionResult *)result error:(NSError **)error {
    __block XBSchemeActionStatus status = XBSchemeActionStatusErrorOccurred;
    BOOL ok = [self perform:error block:^{
        status = (XBSchemeActionStatus)result.result.status;
    }];
    return ok ? @(status) : nil;
}

- (XcodeApplication *)xcodeApplication {
    XcodeApplication *app = (XcodeApplication *)[SBApplication applicationWithBundleIdentifier:@"com.apple.dt.Xcode"];
    app.delegate = self.eventDelegate;
    app.timeout = 10;
    return app;
}

- (BOOL)perform:(NSError **)error block:(void (^)(void))block {
    self.eventDelegate.lastError = nil;

    @try {
        block();
    } @catch (NSException *exception) {
        NSLog(@"xcode-run-bar: Objective-C exception during AppleEvent: name=%@ reason=%@", exception.name, exception.reason);
        [self setError:error code:XBErrorCodeCommandFailed underlying:nil];
        return NO;
    }

    if (self.eventDelegate.lastError) {
        NSLog(@"xcode-run-bar: perform failed with AppleEvent error: domain=%@ code=%ld description=%@", self.eventDelegate.lastError.domain, (long)self.eventDelegate.lastError.code, self.eventDelegate.lastError.localizedDescription);
        [self setError:error code:[self codeForError:self.eventDelegate.lastError] underlying:self.eventDelegate.lastError];
        return NO;
    }

    return YES;
}

- (XBErrorCode)codeForError:(NSError *)error {
    if (error.code == -1743) {
        return XBErrorCodeAutomationPermissionNeeded;
    }
    return XBErrorCodeCommandFailed;
}

- (void)setError:(NSError **)error code:(XBErrorCode)code underlying:(NSError *)underlying {
    if (!error) {
        return;
    }

    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    if (underlying) {
        userInfo[NSUnderlyingErrorKey] = underlying;
    }

    *error = [NSError errorWithDomain:XBErrorDomain code:code userInfo:userInfo];
}

- (NSString *)schemeNameForDocument:(XcodeWorkspaceDocument *)document {
    XcodeScheme *scheme = [self optionalValue:@"workspace.activeScheme" block:^id{
        return document.activeScheme;
    }];
    return [self stringValue:[self optionalValue:@"workspace.activeScheme.name" block:^id{
        return scheme.name;
    }]];
}

- (NSString *)destinationNameForDocument:(XcodeWorkspaceDocument *)document {
    XcodeRunDestination *destination = [self optionalValue:@"workspace.activeRunDestination" block:^id{
        return document.activeRunDestination;
    }];
    NSString *name = [self stringValue:[self optionalValue:@"workspace.activeRunDestination.name" block:^id{
        return destination.name;
    }]];
    if (name.length > 0) {
        return name;
    }

    NSArray<XcodeRunDestination *> *destinations = [[self optionalValue:@"workspace.runDestinations" block:^id{
        return [[document runDestinations] get];
    }] ?: @[] copy];
    NSLog(@"xcode-run-bar: active destination missing; runDestinations count=%lu", (unsigned long)destinations.count);

    for (XcodeRunDestination *candidate in destinations) {
        NSString *candidateName = [self stringValue:[self optionalValue:@"workspace.runDestinations.name" block:^id{
            return candidate.name;
        }]];
        if (candidateName.length > 0) {
            NSLog(@"xcode-run-bar: using fallback destination=%@", candidateName);
            return candidateName;
        }
    }

    return nil;
}

- (id)optionalValue:(NSString *)label block:(id (^)(void))block {
    NSError *previousError = self.eventDelegate.lastError;
    self.eventDelegate.lastError = nil;

    @try {
        id value = block();
        if (self.eventDelegate.lastError) {
            NSLog(@"xcode-run-bar: optional read %@ failed: domain=%@ code=%ld description=%@", label, self.eventDelegate.lastError.domain, (long)self.eventDelegate.lastError.code, self.eventDelegate.lastError.localizedDescription);
            self.eventDelegate.lastError = previousError;
            return nil;
        }
        self.eventDelegate.lastError = previousError;

        if (value == (id)kCFNull || value == [NSNull null]) {
            return nil;
        }
        return value;
    } @catch (NSException *exception) {
        NSLog(@"xcode-run-bar: optional read %@ threw exception: name=%@ reason=%@", label, exception.name, exception.reason);
        self.eventDelegate.lastError = previousError;
        return nil;
    }
}

- (NSString *)stringValue:(id)value {
    if (![value isKindOfClass:NSString.class]) {
        return nil;
    }
    NSString *string = (NSString *)value;
    return string.length > 0 ? string : nil;
}

- (NSString *)pathValue:(id)value {
    if ([value isKindOfClass:NSURL.class]) {
        return [self stringValue:((NSURL *)value).path];
    }
    return [self stringValue:value];
}

- (NSDate *)modificationDateForPath:(NSString *)path {
    NSDictionary<NSFileAttributeKey, id> *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    return attributes[NSFileModificationDate] ?: NSDate.distantPast;
}

@end
