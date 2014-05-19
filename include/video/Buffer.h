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
#ifndef LUBYK_INCLUDE_VIDEO_BUFFER_H_
#define LUBYK_INCLUDE_VIDEO_BUFFER_H_

#include "dub/dub.h"

namespace video {

/** Internal class for video storage.
 * 
 */
class Buffer {
protected:
  /** Holds data for the current frame. Note that this changes
   * on every image frame update.
   */
  unsigned char *frame_;
  size_t frame_len_;
  int width_;
  int height_;
  int elem_size_;
  int padding_;
public:
  Buffer()
    : frame_(NULL)
    , frame_len_(0)
    , width_(0)
    , height_(0)
    , elem_size_(0)
  {}


  virtual ~Buffer() {
    if (frame_) free(frame_);
  }

  /** Return current frame data.
   */
  LuaStackSize frameData(lua_State *L) {
    if (!frame_) return 0;
    lua_pushlightuserdata(L, frame_);
    return 1;
  }

  /** Return current frame size.
   */
  size_t frameSize() {
    return frame_len_;
  }

  LuaStackSize frameInfo(lua_State *L) {
    lua_pushnumber(L, width_);
    lua_pushnumber(L, height_);
    lua_pushnumber(L, elem_size_);
    return 3;
  }

protected:
  bool allocateFrame(int w, int h, int elem) {
    if (frame_) {
      throw dub::Exception("Cannot resize or reallocate frame.");
    }

    size_t len = w * h * elem;
    // alloc
    frame_ = (unsigned char*)malloc(len);
    if (frame_) {
      frame_len_ = len;
      width_     = w;
      height_    = h;
      elem_size_ = elem;
      return true;
    } else {
      return false;
    }
  }

};

} // video

#endif // LUBYK_INCLUDE_VIDEO_BUFFER_H_


