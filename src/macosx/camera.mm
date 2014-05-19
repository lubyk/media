#include "video/Camera.h"

#import <QTKit/QTKit.h>

using namespace video;

/* ======================== Capture delegate ============== */

@interface CaptureDelegate : NSObject {
  Camera *master_;
  Camera::Implementation *impl_;
}

- (id)initWithCamera:(Camera*)master impl:(Camera::Implementation*)impl;
- (void)newFrame;

/* ================ Capture Delegate method ===== 
 NOT CALLED ON MAIN THREAD
 */
- (void)captureOutput:(QTCaptureOutput *)captureOutput didOutputVideoFrame:(CVImageBufferRef)videoFrame withSampleBuffer:(QTSampleBuffer *)sampleBuffer fromConnection:(QTCaptureConnection *)connection;
@end

/* ======================== Camera::Implementation ======= */

class Camera::Implementation {
  Camera *master_;

  CaptureDelegate *capture_delegate_;
  QTCaptureSession *capture_session_;
  QTCaptureDeviceInput *capture_input_;
  QTCaptureDecompressedVideoOutput *capture_output_;

  NSString *device_uid_;
public:
  Implementation(Camera *master, const char *device_uid)
      : master_(master)
      , capture_delegate_(nil)
      , capture_session_(nil)
      , capture_input_(nil)
      , capture_output_(nil)
      , device_uid_(nil)
  {
    if (device_uid) {
      device_uid_ = [[NSString alloc] initWithUTF8String:device_uid];
    }
  }

  ~Implementation() {
    stop();
    if (device_uid_) {
      [device_uid_ release];
    }
  }

  QTCaptureDevice *getDevice() {
    if (device_uid_) {
      return [QTCaptureDevice deviceWithUniqueID:device_uid_];
    } else {
      return [QTCaptureDevice defaultInputDeviceWithMediaType:QTMediaTypeVideo];
    }
  }

  // ---------------------------------------------------------------
  void start() {
    NSError *error = nil;
    if (capture_delegate_) return;

    // Find video device
    QTCaptureDevice *device = getDevice();

    if (!device) {
      throw dub::Exception("Could not find device '%s'.", [device_uid_ UTF8String]);
    }

    if (![device open:&error]) {
      throw dub::Exception("Could not open device '%s' (%s).", [device_uid_ UTF8String], [[error localizedDescription] UTF8String]);
    }

    capture_session_ = [[QTCaptureSession alloc] init];

    // Add the video device to the session as a device input.
    capture_input_ = [[QTCaptureDeviceInput alloc] initWithDevice:device];
    if (![capture_session_ addInput:capture_input_ error:&error]) {
      [capture_session_ release];
      capture_session_ = nil;
      [capture_input_ release];
      capture_input_ = nil;
      throw dub::Exception("Could not add input '%s' to capture session (%s).", [device_uid_ UTF8String], [[error localizedDescription] UTF8String]);
    }

    capture_output_ = [[QTCaptureDecompressedVideoOutput alloc] init];

    capture_delegate_ = [[CaptureDelegate alloc] initWithCamera:master_ impl:this];
    [capture_output_ setDelegate:capture_delegate_];
    // [capture_output_ setAutomaticallyDropsLateVideoFrames:YES];

    NSMutableDictionary* pixelBufferAttributes = [[NSMutableDictionary alloc] init];

    [pixelBufferAttributes
      setObject:[NSNumber numberWithUnsignedInt:k24RGBPixelFormat]
      forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey
    ];

    [capture_output_ setPixelBufferAttributes:pixelBufferAttributes];
    [pixelBufferAttributes release];

    if (![capture_session_ addOutput:capture_output_ error:&error]) {
      [capture_session_ release];
      capture_session_ = nil;
      [capture_input_ release];
      capture_input_ = nil;
      [capture_output_ release];
      capture_output_ = nil;
      [capture_delegate_ release];
      capture_delegate_ = nil;

      throw dub::Exception("Could not add output delegate to capture session. (%s)", [[error localizedDescription] UTF8String]);
    }

    [capture_session_ startRunning];
  }

  // ---------------------------------------------------------------
  void stop() {
    if (capture_delegate_) {
      if ([capture_session_ isRunning]) [capture_session_ stopRunning];

      if (capture_output_) {
        [capture_session_ removeOutput:capture_output_];
        [capture_output_ release];
        capture_output_ = nil;
      }

      if (capture_input_) {
        [capture_session_ removeInput:capture_input_];
        QTCaptureDevice *device = [capture_input_ device];

        if ([device isOpen]) {
          [device close];
        }

        [capture_input_ release];
        capture_input_ = nil;
      }
      [capture_session_ release];
      capture_session_ = nil;

      [capture_delegate_ release];
      capture_delegate_ = nil;
    }
  }

  LuaStackSize __tostring(lua_State *L) {
    // get device name
    @autoreleasepool {
      QTCaptureDevice *device = getDevice();
      if (device == nil) {
        lua_pushfstring(L, "lui.Camera '?': %p", master_);
      } else {
        lua_pushfstring(L, "lui.Camera '%s': %p", [[device localizedDisplayName] UTF8String], master_);
      }
    }
    return 1;
  }

  //===================================================== CAPTURE CALLBACK
  void captureOutput(QTCaptureOutput     *captureOutput,
                     CVImageBufferRef     videoFrame,
                     QTSampleBuffer      *sampleBuffer,
                     QTCaptureConnection *connection) {
    // [sampleBuffer incrementSampleUseCount];
    if (CVPixelBufferLockBaseAddress(videoFrame, kCVPixelBufferLock_ReadOnly) == 0) {
      if (!master_->frame_) {
        if (CVPixelBufferIsPlanar(videoFrame)) {
          fprintf(stderr, "Cannot capture frame with multiple planes (planar data not supported).\n");
          return;
        }
        int w = CVPixelBufferGetWidth(videoFrame);
        int h = CVPixelBufferGetHeight(videoFrame);
        // size_t bytes_per_row = CVPixelBufferGetBytesPerRow(videoFrame);

        int elem = 3; // RGB, cv type CV_8UC3

        size_t pad_l, pad_r, pad_t, pad_b;

        CVPixelBufferGetExtendedPixels(videoFrame, &pad_l, &pad_r, &pad_t, &pad_b);

        size_t step = (w + pad_l + pad_r) * elem;
        size_t padding = (pad_t * step) + (pad_l * elem);

        // cv matrix
        // new Matrix(
        //   w,
        //   h,
        //   CV_8UC3,
        //   (unsigned char*)CVPixelBufferGetBaseAddress(videoFrame) + padding,
        //   step
        // );
        // FIXME: if we have pad_l or pad_r the texture will not work properly.
        if (master_->allocateFrame(w, h, elem)) {
          master_->padding_ = padding;
        } else {
          fprintf(stderr, "Could not allocate frame with size %ix%i, elem size %i.\n", w, h, elem);
        }
      }

      // ======== change data
      memcpy(master_->frame_,
             (unsigned char*)CVPixelBufferGetBaseAddress(videoFrame) + master_->padding_,
             master_->frame_len_);
      CVPixelBufferUnlockBaseAddress(videoFrame, kCVPixelBufferLock_ReadOnly);
      [capture_delegate_ performSelectorOnMainThread:@selector(newFrame) withObject:nil waitUntilDone:NO];
    }

    // [sampleBuffer decrementSampleUseCount];
  }
  
};

/* ======================== CaptureDelegate implementation ======================= */

@implementation CaptureDelegate
- (id)initWithCamera:(Camera*)master impl:(Camera::Implementation*)impl {
  if ( (self = [super init]) ) {
    master_ = master;
    impl_   = impl;
  }
  return self;
}

- (void)newFrame {
  master_->newFrame();
}

/** This callback is NOT CALLED ON MAIN THREAD.
 */
- (void)captureOutput:(QTCaptureOutput *)captureOutput didOutputVideoFrame:(CVImageBufferRef)videoFrame withSampleBuffer:(QTSampleBuffer *)sampleBuffer fromConnection:(QTCaptureConnection *)connection {
  impl_->captureOutput(captureOutput, videoFrame, sampleBuffer, connection);
}

@end

/* ======================== Camera ======================= */

Camera::Camera(const char *device_uid) {
  @autoreleasepool {
    impl_ = new Camera::Implementation(this, device_uid);
  }
}

Camera::~Camera() {
  if (impl_) delete impl_;
}

void Camera::start() {
  impl_->start();
}

void Camera::stop() {
  impl_->stop();
}

LuaStackSize Camera::sources(lua_State *L) {
  @autoreleasepool {
    // return a table with 'device name' => device_uid
    NSEnumerator *list = [[QTCaptureDevice inputDevicesWithMediaType:QTMediaTypeVideo] objectEnumerator];
    QTCaptureDevice *device;
    lua_newtable(L);
    // <tbl>

    while ( (device = [list nextObject]) ) {
      lua_pushstring(L, [[device localizedDisplayName] UTF8String]);
      // <tbl> "name"
      lua_pushstring(L, [[device uniqueID] UTF8String]);
      // <tbl> "name" "uid"
      lua_rawset(L, -3);
    }
  }
  // <tbl>
  return 1;
}

LuaStackSize Camera::__tostring(lua_State *L) {
  return impl_->__tostring(L);
}

