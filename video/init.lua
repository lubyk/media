--[[--------------------
  # Lubyk video <a href="https://travis-ci.org/lubyk/video"><img src="https://travis-ci.org/lubyk/video.png" alt="Build Status"></a> 

  Single-threaded, fast and predictable scheduling with nanosecond precision.

  <html><a href="https://github.com/lubyk/video"><img style="position: absolute; top: 0; right: 0; border: 0;" src="https://s3.amazonaws.com/github/ribbons/forkme_right_green_007200.png" alt="Fork me on GitHub"></a></html>
  
  *MIT license* &copy Gaspard Bucher 2014.

  ## Installation
  
  With [luarocks](http://luarocks.org):

    $ luarocks install video

--]]--------------------
local lub  = require 'lub'
local lib  = lub.Autoload 'video'

-- ## Dependencies

-- Current version respecting [semantic versioning](http://semver.org).
lib.VERSION = '1.0.0'

lib.DEPENDS = { -- doc
  -- Compatible with Lua 5.1, 5.2 and LuaJIT
  "lua >= 5.1, < 5.3",
  -- Uses [Lubyk base library](http://doc.lubyk.org/lub.html)
  'lub >= 1.0.3, < 2.0',
}

-- nodoc
lib.DESCRIPTION = {
  summary = "Lubyk video.",
  detailed = [[
  video.Camera: live video stream from a camera or webcam.

  video.File: read a video from a file.
  ]],
  homepage = "http://doc.lubyk.org/video.html",
  author   = "Gaspard Bucher",
  license  = "MIT",
}

-- nodoc
lib.BUILD = {
  github    = 'lubyk',
  includes  = {'include', 'src/bind'},
  libraries = {'stdc++'},
  platlibs = {
    linux   = {'stdc++', 'rt'},
    macosx  = {
      'stdc++',
      '-framework Foundation',
      '-framework Cocoa',
      '-framework AVFoundation',
      'objc',
    },
  },
}

local gui_running

-- nodoc
function lib.bootstrap(class, orig, ...)
  -- Make sure lui.Application is created first
  if not gui_running then
    gui_running = true
    if coroutine.running() then
      -- Inform scheduler that we need to run the GUI event loop.
      coroutine.yield('gui')
    else
      print("Warning: using video library outside of scheduler does not work if GUI is not running.")
    end
  end
  class.new = orig
  return orig(...)
end

-- # Classes

return lib
