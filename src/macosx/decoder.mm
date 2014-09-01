/**
 * In order to not decode in main thread, we use dispatch queues.
 */

#include "media/Decoder.h"

#import <AVFoundation/AVFoundation.h>

using namespace media;

/* ======================== Decoder::Implementation ======= */

class Decoder::Implementation {
  Decoder *master_;
  NSURL *asset_url_;

  // VIDEO DECODING
  AVAssetReader *asset_reader_;
  AVAssetReaderTrackOutput *asset_output_;

  // IMAGE DECODING
  bool is_image_;
  CVPixelBufferRef pixel_buffer_;
  size_t width_;
  size_t height_;

  // DECODING QUEUE
  dispatch_queue_t decode_queue_;

public:
  Implementation(Decoder *master, bool is_image)
      : master_(master)
      , asset_url_(nil)
      , asset_reader_(nil)
      , asset_output_(nil)
      , is_image_(is_image)
      , pixel_buffer_(NULL)
      , width_(0)
      , height_(0)
      , decode_queue_(NULL)
  {
  }

  ~Implementation() {
    stop();
    if (asset_url_) {
      [asset_url_ release];
    }
  }

  bool isImage() {
    return is_image_;
  }

  void stop() {
    if (decode_queue_) {
      // Do we need to clear the queue ?
      decode_queue_ = nil;
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
    if (pixel_buffer_) {
      CFRelease(pixel_buffer_);
      width_  = 0;
      height_ = 0;
    }
  }

  void start() {
    if (!asset_url_) {
      throw dub::Exception("Cannot start decoding, asset url not set.");
    }
    stop();

    printf("Start\n");

    // get ready for decoding
    // No need to retain or release: automatic garbage collection of queue in os x 10.8+
    decode_queue_ = dispatch_queue_create("org.lubyk media.Decoder Queue", DISPATCH_QUEUE_SERIAL);

    if (is_image_) {
      startImage();
    } else {
      startVideo();
    }
  }


  void startImage() {
    // noop
  }


  void startVideo() {
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

    [asset_reader_ startReading];
  }


  bool nextFrame() {
    if (is_image_) {
      return nextImageFrame();
    } else {
      return nextVideoFrame();
    }
  }

  void loadAsset(const char *asset_url) {
    if (!is_image_) {
      // If we change video, we must stop first. 
      stop();
    }
    asset_url_ = [[NSURL alloc] initFileURLWithPath:[NSString stringWithUTF8String:asset_url]];
    if (!asset_url_) {
      throw dub::Exception("Invalid url '%s'.", asset_url);
    }
  }

  bool nextImageFrame() {
    if (!decode_queue_) start();
    dispatch_async(decode_queue_, ^{
      // Execute in decoder queue.
      CGImageRef image_ref = NULL;

      
      CFStringRef opt_keys[] = {
        kCGImageSourceShouldCache,
        kCGImageSourceShouldAllowFloat,
      };

      CFTypeRef opt_values[] = {
          // FIXME: Should this be true or false ??
          kCFBooleanTrue,
          kCFBooleanFalse,
      };
   
      CFDictionaryRef options = CFDictionaryCreate(NULL,
        (const void **) opt_keys,
        (const void **) opt_values,
        2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
      );

      // Create an image source from the URL.
      CGImageSourceRef image_source = CGImageSourceCreateWithURL((CFURLRef)asset_url_, options);

      CFRelease(options);

      // Make sure the image source exists before continuing
      if (image_source == NULL){
        // FIXME: error reporting on main thread.
        printf("Could not decode image '%s' !", [[asset_url_ absoluteString] UTF8String]);
      } else {
        // Create an image from the first item in the image source.
        image_ref = CGImageSourceCreateImageAtIndex(image_source, 0, NULL);

        CFRelease(image_source);

        if (!decode_queue_) {
          // reader could be stoped before image is decoded.
          if (image_ref) {
            CFRelease(image_ref);
          }
        } else {
          if (image_ref) {
            CVImageBufferRef frame = pixelFromImage(image_ref);
            processFrame(frame);
            CFRelease(image_ref);
          } else {
            // FIXME: error reporting on main thread.
            printf("Could not decode image '%s' !", [[asset_url_ absoluteString] UTF8String]);
          }
        }
      }
    });

    return true;
  }

  CVImageBufferRef pixelFromImage(CGImageRef image) {
    size_t width  = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    
    if (pixel_buffer_ && width_ == width && height_ == height) {
      // ok, nothing to change, we write in same buffer
      // Do we need CVPixelBufferPool or can we reuse pour pixel_buffer_ ?
    } else {
      if (pixel_buffer_) {
        CFRelease(pixel_buffer_);
        pixel_buffer_ = NULL;
      }

      CFStringRef opt_keys[] = {
        kCVPixelBufferCGImageCompatibilityKey,
        kCVPixelBufferCGBitmapContextCompatibilityKey,
      };

      CFTypeRef opt_values[] = {
          kCFBooleanTrue,
          kCFBooleanTrue,
      };

      CFDictionaryRef options = CFDictionaryCreate(NULL,
        (const void **) opt_keys,
        (const void **) opt_values,
        2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
      );
        
      CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, width,
          height,  kCVPixelFormatType_32BGRA, (CFDictionaryRef) options, 
          &pixel_buffer_);

      CFRelease(options);

      if (status != kCVReturnSuccess || pixel_buffer_ == NULL) {
        printf("Could not create pixel buffer.");
        pixel_buffer_ = NULL;
        return NULL;
      }
      width_  = width;
      height_ = height;
    }

    // Write image in pixel buffer

    CVPixelBufferLockBaseAddress(pixel_buffer_, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pixel_buffer_);


    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();

    // FIXME: Support alpha channel !!
    CGContextRef context = CGBitmapContextCreate(pxdata, width,
        height, 8, CVPixelBufferGetBytesPerRow(pixel_buffer_),
        rgbColorSpace, 
        kCGImageAlphaNoneSkipLast);

    
    // Do not flip image so that this works the same way as video.
    // or find a way to flip video image.
    // CGContextTranslateCTM(context, 0, height);
    // CGContextScaleCTM(context, 1.0, -1.0);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);

    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);

    CVPixelBufferUnlockBaseAddress(pixel_buffer_, 0);

    return pixel_buffer_;
  }

  bool nextVideoFrame() {
    if (!asset_reader_) start();

    if ([asset_reader_ status] == AVAssetReaderStatusReading) {

      // Asset reader can change between now and end of block execution.
      // protect by using a local variable. The block will retain so we do
      // not have to retain/release.
      AVAssetReader *asset_reader = asset_reader_;
      AVAssetReaderTrackOutput *asset_output = asset_output_;
      dispatch_async(decode_queue_, ^{
        // Execute in video queue.
        if ([asset_reader status] == AVAssetReaderStatusReading) {
          // asset_reader could be halted between calls.
          CMSampleBufferRef buffer = [asset_output copyNextSampleBuffer];
          if (buffer) {
            CVImageBufferRef frame = CMSampleBufferGetImageBuffer(buffer);
            processFrame(frame);
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
  void processFrame(CVImageBufferRef frame) {

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

Decoder::Decoder(bool is_image_) {
  @autoreleasepool {
    impl_ = new Decoder::Implementation(this, is_image_);
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

void Decoder::loadAsset(const char *url) {
  impl_->loadAsset(url);
}

bool Decoder::isImage() {
  return impl_->isImage();
}

LuaStackSize Decoder::__tostring(lua_State *L) {
  return impl_->__tostring(L);
}


