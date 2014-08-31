--[[------------------------------------------------------

  # Camera

  Access to video capture devices. The implementation has
  been optimized to avoid copying data. This means that the
  #frameData is an internal buffer that can be overwriten.

  Usage example:

    local media = require 'media'

    -- List sources
    for name, uid in pairs(media.Camera.sources()) do
      print(name, uid)
    end

    -- Create camera object from default video source
    camera = media.Camera()

    -- Setup callback on new frames
    function camera:newFrame()
      print('new frame', 'size', camera:frameLength())
      -- camera:frameData() --> lightuserdata void*
    end

    -- Start capturing frames.
    camera:start()
--]]------------------------------------------------------
local media = require 'media'
local core  = require 'media.core'
local lib   = core.Camera
local o_new = lib.new

-- # Constructor
--
-- Create a camera object. If `device_uid` is not provided, uses the default
-- video capture device (or the first). The `new_frame` callback function can
-- also be set with #newFrame.
-- function new(device_uid, callback)

local function new(device_uid, callback)
  local self
  if device_uid then
    self = o_new(device_uid)
  else
    self = o_new()
  end
  self.newFrame = callback
  return self
end

-- nodoc
function lib.new(...)
  -- Ensures gui is running when creating first Camera object.
  return media.bootstrap(lib, new, ...)
end

-- # Methods

-- Get a lightuserdata pointer to the current frame data. The content of the
-- referenced memory can changes between 'newFrame' calls.
-- function lib.frameData()

-- Get a frame data size in bytes.
-- function lib.frameSize()

-- # Callback

-- This is called every time a new frame arrives from the capture device. It is
-- only safe to access the frameData
-- function lib:newFrame

return lib

