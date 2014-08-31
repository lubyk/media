/**
 * In order to not decode in main thread, we use dispatch queues.
 */

#include "video/Decoder.h"

#import <AVFoundation/AVFoundation.h>

using namespace video;

/* ======================== Decoder::Implementation ======= */

class Decoder::Implementation {
  Decoder *master_;
  NSURL *asset_url_;

  AVAssetReader *asset_reader_;
  AVAssetReaderTrackOutput *asset_output_;

  dispatch_queue_t video_queue_;

public:
  Implementation(Decoder *master, const char *asset_url)
      : master_(master)
      , asset_url_(nil)
      , asset_reader_(nil)
      , asset_output_(nil)
      , video_queue_(NULL)
  {
    // NSURL acc
    //asset_url_ = [[NSURL alloc] initWithString:[NSString stringWithUTF8String:asset_url]];
    asset_url_ = [[NSURL alloc] initFileURLWithPath:[NSString stringWithUTF8String:asset_url]];
    if (!asset_url_) {
      throw dub::Exception("Invalid url '%s'.", asset_url);
    }
  }

  ~Implementation() {
    stop();
  }


  void stop() {
    if (video_queue_) {
    }
    if (asset_reader_) {
      [asset_reader_ cancelReading];
      [asset_reader_ release];
      asset_reader_ = nil;
    }
    if (asset_output_) {
      [asset_output_ release];
      asset_output_ = nil;
    }
  }

  void start() {
    stop();

    printf("Start\n");
    // AVAsset *asset = [AVAsset assetWithURL:asset_url_];
    NSDictionary *options = @{ AVURLAssetPreferPreciseDurationAndTimingKey : @YES };
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:asset_url_ options:options];
    
    if (!asset) {
      throw dub::Exception("Could not create AVAsset with url '%s'.", [[asset_url_ absoluteString] UTF8String]);
    }
    printf("Created AVAsset with url '%s'.\n", [[asset_url_ absoluteString] UTF8String]);

    // [asset loadValuesAsynchronouslyForKeys:@[@"tracks", @"duration"]
    //                     completionHandler:^{}];

    NSError *error = nil;
    asset_reader_ = [[AVAssetReader alloc] initWithAsset:asset error:&error];
    if (error) {
      // FIXME
      if (asset_reader_) [asset_reader_ release];
      throw dub::Exception("Could not create asset reader '%s' (%s).", [[asset_url_ absoluteString] UTF8String], [[error localizedDescription] UTF8String]);
    }

    NSArray* video_tracks = [asset tracksWithMediaType:AVMediaTypeVideo]; 
    if ([video_tracks count] < 1) {
      [asset_reader_ release];
      throw dub::Exception("No video track found in '%s'.", [[asset_url_ absoluteString] UTF8String]);
    }
    AVAssetTrack* video_track = [video_tracks objectAtIndex:0];

    // Use BGRA as this is the fastest from hardware
    asset_output_ = [[AVAssetReaderTrackOutput alloc] 
        initWithTrack:video_track
       outputSettings:@{(NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    
    asset_output_.alwaysCopiesSampleData = NO;
    [asset_reader_ addOutput:asset_output_];

    // get ready for decoding
    // No need to retaion or release: automatic garbage collection of queue in os x 10.8+
    video_queue_ = dispatch_queue_create("org.lubyk video.Decoder Queue", DISPATCH_QUEUE_SERIAL);
    [asset_reader_ startReading];
  }


  bool nextFrame() {
    if (!asset_reader_) start();

    if ([asset_reader_ status] == AVAssetReaderStatusReading) {

      // Asset reader can change between now and end of block execution.
      // protect by using a local variable. The block will retain so we do
      // not have to retain/release.
      AVAssetReader *asset_reader = asset_reader_;
      AVAssetReaderTrackOutput *asset_output = asset_output_;
      dispatch_async(video_queue_, ^{
        // Execute in video queue.
        if ([asset_reader status] == AVAssetReaderStatusReading) {
          // asset_reader could be halted between calls.
          CMSampleBufferRef buffer = [asset_output copyNextSampleBuffer];
          if (buffer) {
            processFrame(buffer);
            CMSampleBufferInvalidate(buffer);
            CFRelease(buffer);   
          }
        }
      });
      return true;
    } else {
      return false;
    }
  }

  LuaStackSize __tostring(lua_State *L) {
    // get device name
    @autoreleasepool {
      lua_pushfstring(L, "lui.Decoder '%s': %p", [[asset_url_ absoluteString] UTF8String], master_);
    }
    return 1;
  }

  //===================================================== CAPTURE CALLBACK
  void processFrame(CMSampleBufferRef sampleBuffer) {
    CVImageBufferRef frame = CMSampleBufferGetImageBuffer(sampleBuffer);

    // This code is the same as Camera.mm could we DRY without loosing performance ?
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
      // Since we dispatch_sync, we wait until done and memcpy
      // is guaranteed to not occur during 'newFrame' callback.

      dispatch_sync(dispatch_get_main_queue(), ^{
        // Performed on main thread.
        master_->newFrame();
      });
      // wait until done to process next element in queue.
    }
  }
  
};

/* ======================== Decoder ======================= */

Decoder::Decoder(const char *device_uid) {
  @autoreleasepool {
    impl_ = new Decoder::Implementation(this, device_uid);
  }
}

Decoder::~Decoder() {
  if (impl_) delete impl_;
}

void Decoder::start() {
  impl_->start();
}

void Decoder::stop() {
  impl_->stop();
}

bool Decoder::nextFrame() {
  return impl_->nextFrame();
}

LuaStackSize Decoder::__tostring(lua_State *L) {
  return impl_->__tostring(L);
}


