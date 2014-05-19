package = "video"
version = "1.0.0-1"
source = {
  url = 'https://github.com/lubyk/video/archive/REL-1.0.0.tar.gz',
  dir = 'video-REL-1.0.0',
}
description = {
  summary = "Lubyk video.",
  detailed = [[
    video.Camera: live video stream from a camera or webcam.

    video.File: read a video from a file.
    ]],
  homepage = "http://doc.lubyk.org/video.html",
  license = "MIT"
}

dependencies = {
  "lua >= 5.1, < 5.3",
  "lub >= 1.0.3, < 1.1",
}
build = {
  type = 'builtin',
  modules = {
    -- Plain Lua files
    ['video'          ] = 'video/init.lua',
    ['video.Camera'   ] = 'video/Camera.lua',
    ['video.File'     ] = 'video/File.lua',
    -- C module
    ['video.core'     ] = {
      sources = {
        'src/bind/dub/dub.cpp',
        'src/bind/video_Buffer.cpp',
        'src/bind/video_Camera.cpp',
        'src/bind/video_core.cpp',
      },
      incdirs   = {'include', 'src/bind'},
      libraries = {'stdc++'},
    },
  },
  platforms = {
    linux = {
      modules = {
        ['video.core'] = {
          libraries = {'stdc++', 'rt'},
        },
      },
    },
    macosx = {
      modules = {
        ['video.core'] = {
          sources = {
            [5] = 'src/macosx/camera.mm',
          },
          libraries = {'stdc++', '-framework Foundation', '-framework Cocoa', '-framework QTKit', 'objc'},
        },
      },
    },
  },
}
