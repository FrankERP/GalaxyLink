#ifndef CGVirtualDisplayShim_h
#define CGVirtualDisplayShim_h
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Declarations for the private CoreGraphics virtual display API.
// Same class shape used by FluffyDisplay and Deskreen; may change in a
// future macOS release — all usage is isolated in VirtualDisplay.swift.

@class CGVirtualDisplay;

NS_ASSUME_NONNULL_BEGIN

@interface CGVirtualDisplayDescriptor : NSObject
@property(strong, nonatomic) dispatch_queue_t queue;
@property(strong, nonatomic) NSString *name;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) CGPoint redPrimary;
@property(nonatomic) CGPoint greenPrimary;
@property(nonatomic) CGPoint bluePrimary;
@property(nonatomic) CGPoint whitePoint;
@property(copy, nonatomic) void (^terminationHandler)(id, CGVirtualDisplay *);
@property(nonatomic) unsigned int vendorID;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int serialNum;
- (instancetype)init;
@end

@interface CGVirtualDisplayMode : NSObject
@property(readonly, nonatomic) unsigned int width;
@property(readonly, nonatomic) unsigned int height;
@property(readonly, nonatomic) double refreshRate;
- (instancetype)initWithWidth:(unsigned int)width
                       height:(unsigned int)height
                  refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(strong, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property(nonatomic) unsigned int hiDPI;
- (instancetype)init;
@end

@interface CGVirtualDisplay : NSObject
@property(readonly, nonatomic) CGDirectDisplayID displayID;
@property(readonly, nonatomic) unsigned int hiDPI;
@property(readonly, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
- (nullable instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

NS_ASSUME_NONNULL_END

#endif
