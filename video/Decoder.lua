--[[------------------------------------------------------

  # Decoder

  Access to video capture devices. The implementation has
  been optimized to avoid copying data. This means that the
  #frameData is an internal buffer that can be overwriten.

  Usage example:

    local video = require 'video'

    -- Create decoder from file
    movie = video.Decoder('/some/path/to/video.mp4')

    -- Setup callback on new frames
    function movie:newFrame()
      print('new frame', 'size', camera:frameLength())
      -- movie:frameData() --> lightuserdata void*
    end

    -- Read frames at regular intervals
    tim = lens.Timer(1/30, function()
      movie:nextFrame()
    end)

    TODO: movie:start() should create timer with frame rate.

--]]------------------------------------------------------
local video = require 'video'
local core  = require 'video.core'
local lib   = core.Decoder
local o_new = lib.new

-- # Constructor
--
-- Create a decoder object from a movie given by a path or url.
-- The `new_frame` callback function can also be set with #newFrame.
-- function new(asset_url, callback)

local function new(asset_url, callback)
  local self
  if asset_url then
    self = o_new(asset_url)
  else
    self = o_new()
  end
  self.newFrame = callback
  return self
end

-- nodoc
function lib.new(...)
  -- Ensures gui is running when creating first Decoder object.
  return video.bootstrap(lib, new, ...)
end

-- # Methods

-- Get a lightuserdata pointer to the current frame data. The content of the
-- referenced memory can changes between 'newFrame' calls.
-- function lib.frameData()

-- Get a frame data size in bytes.
-- function lib.frameSize()

-- # Callback
--
-- This is called every time a new frame arrives from the capture device.
-- function lib:newFrame

return lib
