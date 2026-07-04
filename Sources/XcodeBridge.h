#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const XBErrorDomain;

typedef NS_ENUM(NSInteger, XBErrorCode) {
    XBErrorCodeXcodeNotRunning = 1,
    XBErrorCodeAutomationPermissionNeeded = 2,
    XBErrorCodeCommandFailed = 3,
};

typedef NS_ENUM(NSInteger, XBSchemeActionStatus) {
    XBSchemeActionStatusNotYetStarted = 'srsn',
    XBSchemeActionStatusRunning = 'srsr',
    XBSchemeActionStatusCancelled = 'srsc',
    XBSchemeActionStatusFailed = 'srsf',
    XBSchemeActionStatusErrorOccurred = 'srse',
    XBSchemeActionStatusSucceeded = 'srss',
};

@interface XBWorkspaceSnapshot : NSObject

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, copy, readonly) NSString *schemeName;
@property (nonatomic, copy, readonly) NSString *destinationName;
@property (nonatomic, copy, readonly) NSDate *modificationDate;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface XBActionResult : NSObject

- (instancetype)init NS_UNAVAILABLE;

@end

@interface XcodeBridge : NSObject

@property (nonatomic, readonly) BOOL isXcodeRunning;

- (NSArray<XBWorkspaceSnapshot *> * _Nullable)fetchWorkspacesAndReturnError:(NSError **)error;
- (XBActionResult * _Nullable)runWorkspace:(XBWorkspaceSnapshot *)workspace error:(NSError **)error;
- (BOOL)stopWorkspace:(XBWorkspaceSnapshot *)workspace error:(NSError **)error;
- (BOOL)focusWorkspace:(XBWorkspaceSnapshot *)workspace error:(NSError **)error;
- (NSNumber * _Nullable)completedValueForAction:(XBActionResult *)result error:(NSError **)error;
- (NSNumber * _Nullable)statusValueForAction:(XBActionResult *)result error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
