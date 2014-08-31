/*
  ==============================================================================

   This file is part of the LUBYK project (http://lubyk.org)
   Copyright (c) 2007-2014 by Gaspard Bucher (http://teti.ch).

  ------------------------------------------------------------------------------

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
   THE SOFTWARE.

  ==============================================================================
*/
#ifndef LUBYK_INCLUDE_MEDIA_DECODER_H_
#define LUBYK_INCLUDE_MEDIA_DECODER_H_

#include "media/Buffer.h"
#include "dub/dub.h"

namespace media {

/** Get video from an external camera or webcam.
 * 
 * @dub push: dub_pushobject
 *      ignore: newFrame
 */
class Decoder : public Buffer, public dub::Thread {
public:
  /** Create decoder with asset (mp4 file) url or path.
   */
  Decoder(bool is_image);

  virtual ~Decoder();

  /** Get ready for decoding or restart.
   * This is called implicetely on first #nextFrame call.
   */
  void start();

  /** Stop decoding.
   */
  void stop();

  /** Get next frame. When the frame is available, the callback 'newFrame' is
   * called. This operation is synchronous with frame decoding on Mac OS X.
   *
   * If the read head reaches the end, returns false.
   */
  bool nextFrame();

  /** Load another asset. If the frame/image is the same size, internal memory
   * can be reused.
   */
  void loadAsset(const char *url);

  bool isImage();

  /** String representation.
   */
  LuaStackSize __tostring(lua_State *L);

  // ================================= CALLBACKS

  void newFrame() {
    if (!dub_pushcallback("newFrame")) return;
    // <func> <self>
    dub_call(1, 0);
  }

  class Implementation;
private:
  Implementation *impl_;
};

} // media

#endif // LUBYK_INCLUDE_MEDIA_DECODER_H_


