--
-- Update binding files for this project
--
local lub = require 'lub'
local dub = require 'dub'

local ins = dub.Inspector {
  INPUT    = {
    lub.path '|../include/video',
  },
  --doc_dir = base .. '/tmp',
  --html = true,
  --keep_xml = true,
}

local binder = dub.LuaBinder()

binder:bind(ins, {
  output_directory = lub.path '|../src/bind',
  -- Remove this part in included headers
  header_base = lub.path '|../include',
  -- Create a single library.
  single_lib = 'video',
  -- Open the library with require 'video.core' (not 'video')
  luaopen    = 'video_core',
})
