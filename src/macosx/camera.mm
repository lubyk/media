#include "video/Camera.h"

#import <AVFoundation/AVFoundation.h>

using namespace video;

/* ======================== Capture delegate ============== */

@interface CaptureDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate> {
  Camera *master_;
  Camera::Implementation *impl_;
}

- (id)initWithCamera:(Camera*)master impl:(Camera::Implementation*)impl;
- (void)newFrame;

/* ================ Capture Delegate method ===== 
 NOT CALLED ON MAIN THREAD
 */
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection;
@end

/* ======================== Camera::Implementation ======= */

class Camera::Implementation {
  Camera *master_;

  CaptureDelegate *capture_delegate_;
  AVCaptureSession *capture_session_;
	AVCaptureConnection *video_connection_;

  NSString *device_uid_;
public:
  Implementation(Camera *master, const char *device_uid)
      : master_(master)
      , capture_delegate_(nil)
      , capture_session_(nil)
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

  AVCaptureDevice *getDevice() {
    if (device_uid_) {
      return [AVCaptureDevice deviceWithUniqueID:device_uid_];
    } else {
      return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
  }

  // ---------------------------------------------------------------
  void start() {
    NSError *error = nil;
    if (capture_delegate_) return;

    // Find video device
    AVCaptureDevice *device = getDevice();

    if (!device) {
      throw dub::Exception("Could not find device '%s'.", [device_uid_ UTF8String]);
    }

    capture_session_ = [[AVCaptureSession alloc] init];
    
    // Add the video device to the session as a device input.

    AVCaptureDeviceInput *video_in = [[AVCaptureDeviceInput alloc] initWithDevice:device error:&error];
    if (!video_in) {
      // not OK
      [capture_session_ release];
      capture_session_ = nil;
      throw dub::Exception("Could not add input '%s' to capture session (%s).", [device_uid_ UTF8String], [[error localizedDescription] UTF8String]);
    }

    if (![capture_session_ canAddInput:video_in]) {
      // cannot add
      [capture_session_ release];
      capture_session_ = nil;
      throw dub::Exception("Cannot add input '%s' to capture session.", [device_uid_ UTF8String]);
    }
    [capture_session_ addInput:video_in];
    [video_in release];

    // Add the video output device to the session.

    AVCaptureVideoDataOutput *video_out = [[AVCaptureVideoDataOutput alloc] init];
    [video_out setAlwaysDiscardsLateVideoFrames:YES];

    // Use BGRA as this is the fastest from hardware
    [video_out setVideoSettings:[NSDictionary dictionaryWithObject:
        [NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                         forKey:(id)kCVPixelBufferPixelFormatTypeKey]];

    // Capture delegate
    capture_delegate_ = [[CaptureDelegate alloc] initWithCamera:master_ impl:this];

    // Dispatch queue
    dispatch_queue_t videoCaptureQueue = dispatch_queue_create("org.lubyk video.Camera Queue", DISPATCH_QUEUE_SERIAL);
    [video_out setSampleBufferDelegate:capture_delegate_ queue:videoCaptureQueue];
    dispatch_release(videoCaptureQueue);

    if (![capture_session_ canAddOutput:video_out]) {
      // cannot add
      [capture_session_ release];
      capture_session_ = nil;
      throw dub::Exception("Cannot add output  to capture session.", [device_uid_ UTF8String]);
    }
    [capture_session_ addOutput:video_out];
    video_connection_ = [video_out connectionWithMediaType:AVMediaTypeVideo];

    [capture_session_ startRunning];
  }

  // ---------------------------------------------------------------
  void stop() {
    if (capture_delegate_) {
      if ([capture_session_ isRunning]) [capture_session_ stopRunning];

      [capture_session_ release];
      capture_session_ = nil;
      video_connection_ = nil;

      [capture_delegate_ release];
      capture_delegate_ = nil;
    }
  }

  LuaStackSize __tostring(lua_State *L) {
    // get device name
    @autoreleasepool {
      AVCaptureDevice *device = getDevice();
      if (device == nil) {
        lua_pushfstring(L, "lui.Camera '?': %p", master_);
      } else {
        lua_pushfstring(L, "lui.Camera '%s': %p", [[device localizedName] UTF8String], master_);
      }
    }
    return 1;
  }

  //===================================================== CAPTURE CALLBACK
  void processFrame(CMSampleBufferRef sampleBuffer) {
    CVImageBufferRef frame = CMSampleBufferGetImageBuffer(sampleBuffer);

    if (CVPixelBufferLockBaseAddress(frame, kCVPixelBufferLock_ReadOnly) == 0) {
      if (!master_->frame_) {
        if (CVPixelBufferIsPlanar(frame)) {
          fprintf(stderr, "Cannot capture frame with multiple planes (planar data not supported).\n");
          return;
        }
        // How do frame dimensions relate to pixel buffer dimensions ?
        // CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        // CMVideoDimensions size = CMVideoFormatDescriptionGetDimensions( format );
        // CMVideoCodecType  type = CMFormatDescriptionGetMediaSubType( format );
        // CMTime timestamp = CMSampleBufferGetPresentationTimeStamp( sampleBuffer );

        int w = CVPixelBufferGetWidth(frame);
        int h = CVPixelBufferGetHeight(frame);
        // size_t bytes_per_row = CVPixelBufferGetBytesPerRow(frame);

        int elem = 4; // BGRA

        size_t pad_l, pad_r, pad_t, pad_b;

        CVPixelBufferGetExtendedPixels(frame, &pad_l, &pad_r, &pad_t, &pad_b);

        size_t step = (w + pad_l + pad_r) * elem;
        size_t padding = (pad_t * step) + (pad_l * elem);

        // cv matrix
        // new Matrix(
        //   w,
        //   h,
        //   CV_8UC3,
        //   (unsigned char*)CVPixelBufferGetBaseAddress(frame) + padding,
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
          (unsigned char*)CVPixelBufferGetBaseAddress(frame) + master_->padding_,
          master_->frame_len_);
      CVPixelBufferUnlockBaseAddress(frame, kCVPixelBufferLock_ReadOnly);
      [capture_delegate_ performSelectorOnMainThread:@selector(newFrame) withObject:nil waitUntilDone:NO];
    }
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
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
  // if we were capturing audio, we would need to check connection == video_connection_.
  impl_->processFrame(sampleBuffer);
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
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    lua_newtable(L);
    // <tbl>

    for (AVCaptureDevice *device in devices) {
      lua_pushstring(L, [[device localizedName] UTF8String]);
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

