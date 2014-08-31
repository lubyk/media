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
local lib   = core.Decoder
local o_new = lib.new

local IMAGE_EXT = {
  jpg = true,
  png = true,
}

local nextFrame = lib.nextFrame
local nextImageInFolder

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
    self.nextFrame = nextImageInFolder
  else
    local _, _, ext = string.find(asset_url, "%.(%w+)")
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

-- Get a lightuserdata pointer to the current frame data. The content of the
-- referenced memory can changes between 'newFrame' calls.
-- function lib.frameData()

-- Get a frame data size in bytes.
-- function lib.frameSize()

-- Load another asset.
-- function lib:loadAsset(asset_url)

-- # Callback
--
-- This is called every time a new frame arrives from the capture device.
-- function lib:newFrame

---------- PRIVATE
function nextImageInFolder(self)
  local i = self.images_i + 1
  local path = self.images[i]
  if not path then
    i = 1
    path = self.images[i]
  end
  self.images_i = i
  self:loadAsset(path)
  return nextFrame(self)
end

return lib
