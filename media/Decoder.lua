--[[------------------------------------------------------

  # Decoder

  Access to video capture devices. The implementation has
  been optimized to avoid copying data. This means that the
  #frameData is an internal buffer that can be overwriten.

  Usage example:

    local media = require 'media'

    -- Create decoder from file
    movie = media.Decoder('/some/path/to/video.mp4')

    -- Setup callback on new frames
    function movie:newFrame()
      print('new frame', 'size', camera:frameLength())
      -- movie:frameData() --> lightuserdata void*
    end

    -- Read frames at regular intervals
    tim = lens.Timer(1/30, function()
      -- Ask for next frame (the callback 'newFrame' will be
      -- called when the frame is decoded).
      movie:nextFrame()
    end)

    TODO: movie:start() should create timer with frame rate.

--]]------------------------------------------------------
local lub   = require 'lub'
local media = require 'media'
local core  = require 'media.core'
local four
local lib   = core.Decoder
local o_new = lib.new

local IMAGE_EXT = {
  jpg = true,
  png = true,
}

local nextFrame = lib.nextFrame
local getImageInFolder, prevImageInFolder

-- # Constructor
--
-- Create a decoder object from an asset given by a path or url. The
-- asset can be a video or image. It can also be a path to a folder.
-- The `new_frame` callback function can also be set with #newFrame.
-- function new(asset_url, new_frame)

local function new(asset_url, new_frame)
  local is_image
  local self
  if lub.fileType(asset_url) == 'directory' then
    local images = {}
    for path in lub.Dir(asset_url):list() do
      local _, _, ext = string.find(path, "%.([a-z]+)")
      if IMAGE_EXT[ext] then
        table.insert(images, path)
      end
    end
    table.sort(images)
    if not images[1] then
      error("No compatible image found in folder '"..asset_url.."'.")
    end
    self = o_new(true)
    self.images = images
    self.images_i = 0
    self.nextFrame = getImageInFolder
  else
    local _, _, ext = string.find(asset_url, "%.(%w+)$")
    local is_image = ext and IMAGE_EXT[string.lower(ext)]
    self = o_new(is_image)
    if asset_url then
      self:loadAsset(asset_url)
    end
  end

  self.newFrame = new_frame
  return self
end

-- nodoc
function lib.new(...)
  -- Ensures gui is running when creating first Decoder object.
  return media.bootstrap(lib, new, ...)
end

-- # Methods

-- Ask for next frame. If `blocking` is true, decode frame synchronously.
-- FIXME: blocking only works for images at the moment.
-- function lib:nextFrame(blocking)

-- Ask for the previous frame (folder of images only).
function lib:prevFrame(blocking)
  return getImageInFolder(self, blocking, -1)
end

-- Get a lightuserdata pointer to the current frame data. The content of the
-- referenced memory can changes between 'newFrame' calls.
-- function lib.frameData()

-- Get a frame data size in bytes.
-- function lib.frameSize()

-- Load another asset.
-- function lib:loadAsset(asset_url)

-- Get four.Texture (OpenGL texture).
function lib:texture()
  local w, h = self:frameInfo()
  if self.ftex then
    if self.ftex.size[1] ~= w or
       self.ftex.size[2] ~= h then
      -- create new texture
    else
      -- mark as dirty
      self.ftex.data.updated = true
      return self.ftex
    end
  end

  if not four then
    four = require 'four'
  end

  local V3, Texture = four.V3, four.Texture

  local data = four.Buffer {
    scalar_type = four.Buffer.UNSIGNED_BYTE,
    cdata = function() return self:frameData() end,
    csize = function() return self:frameSize() end,
  }
  self.data = data
  
  self.ftex = Texture { 
    type = Texture.TYPE_2D, 
    internal_format = self:isImage() and Texture.RGBA_8UN or Texture.BGRA_8UN,
    size = V3(w, h, 1),
    wrap_s = Texture.WRAP_CLAMP_TO_EDGE,
    wrap_t = Texture.WRAP_CLAMP_TO_EDGE,
    mag_filter = Texture.MAG_LINEAR,
    min_filter = Texture.MIN_LINEAR_MIPMAP_LINEAR,
    generate_mipmaps = true, 
    data = data
  }
  return self.ftex
end

-- # Callback
--
-- This is called every time a new frame arrives from the capture device.
-- function lib:newFrame

---------- PRIVATE
function getImageInFolder(self, blocking, dir)
  local blocking = blocking or false
  local dir = dir or 1
  local i = self.images_i + dir
  if i <= 0 then
    i = #self.images
  end
  local path = self.images[i]
  if not path then
    i = 1
    path = self.images[i]
  end
  self.images_i = i
  self:loadAsset(path)
  return nextFrame(self, blocking)
end

return lib
