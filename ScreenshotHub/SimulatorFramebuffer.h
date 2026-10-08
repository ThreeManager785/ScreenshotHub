#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SimulatorTouchPhase) {
    SimulatorTouchPhaseBegan,
    SimulatorTouchPhaseMoved,
    SimulatorTouchPhaseEnded
};

NS_SWIFT_SENDABLE
@interface SimulatorFramebuffer : NSObject
- (void)startWithDeviceID:(NSString *)deviceID
      developerDirectory:(NSString *)developerDirectory
                 isWatch:(BOOL)isWatch
            frameHandler:(void (^)(CGImageRef image, unsigned int inputOrientation))frameHandler
          failureHandler:(void (^)(NSError *error))failureHandler;
- (void)sendTouchAtPoint:(CGPoint)point
                   phase:(SimulatorTouchPhase)phase
        inputOrientation:(unsigned int)inputOrientation
              completion:(void (^)(NSError * _Nullable error))completion;
- (void)sendCrownPressed:(BOOL)isPressed completion:(void (^)(NSError * _Nullable error))completion;
- (void)sendCrownRotation:(double)delta completion:(void (^)(NSError * _Nullable error))completion;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
