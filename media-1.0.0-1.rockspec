package = "media"
version = "1.0.0-1"
source = {
  url = 'git://github.com/lubyk/media',
  tag = 'REL-1.0.0',
  dir = 'media',
}
description = {
  summary = "Lubyk media.",
  detailed = [[
  media.Camera: live video stream from a camera or webcam.

  media.Decoder: read a video from a file.
  ]],
  homepage = "http://doc.lubyk.org/media.html",
  license = "MIT"
}

dependencies = {
  "lua >= 5.1, < 5.3",
  "lub >= 1.0.3, < 2.0",
}
build = {
  type = 'builtin',
  modules = {
    -- Plain Lua files
    ['media'          ] = 'media/init.lua',
    ['media.Camera'   ] = 'media/Camera.lua',
    ['media.Decoder'  ] = 'media/Decoder.lua',
    -- C module
    ['media.core'     ] = {
      sources = {
        'src/bind/dub/dub.cpp',
        'src/bind/media_Buffer.cpp',
        'src/bind/media_Camera.cpp',
        'src/bind/media_Decoder.cpp',
        'src/bind/media_core.cpp',
      },
      incdirs   = {'include', 'src/bind'},
      libraries = {'stdc++'},
    },
  },
  platforms = {
    linux = {
      modules = {
        ['media.core'] = {
          sources = {
          },
          libraries = {'stdc++', 'rt'},
        },
      },
    },
    macosx = {
      modules = {
        ['media.core'] = {
          sources = {
            [6] = 'src/macosx/camera.mm',
            [7] = 'src/macosx/decoder.mm',
          },
          libraries = {'stdc++', '-framework Foundation', '-framework Cocoa', '-framework AVFoundation', '-framework ImageIO', 'objc'},
        },
      },
    },
  },
}

