--[[------------------------------------------------------

  # Live shader coding

  In this tutorial, we create a simple animation with
  [lui](http://doc.lubyk.org/lui.html) and [four](http://doc.lubyk.org/four.html),
  showing how to connect all the pieces together from window declaration and
  callbacks to timers, geometry and effects.

  ![effect screenshot](example/lui/LiveShader.jpg)

  Note that you must run this example with `luajit` since plain lua is not
  supported by four.

  ## Download source

  [LiveFloor.lua](example/video/LiveFloor.lua)

--]]------------------------------------------------------
-- doc:lit

-- # Require
--
-- Every script must start by requiring needed libraries. `lui` is the simple
-- lua gui, `four` is the opengl library and `lens` is the scheduling library.
local lens  = require 'lens'
local lui   = require 'lui'
local four  = require 'four'
local video = require 'video'

-- Autoload this script.
lens.run(function() lens.FileWatch() end)

-- Declare some constants.
local WIN_SIZE   = {w = 400, h = 400}
local WIN_POS    = {x = 10 , y = 10 }
local SATURATION = 0.4

-- # Geometry
--
-- Our geometry is going to be a mesh of points on a surface. Exemple for two
-- rows and two columns:
--
--   #txt
--   6 --- 7 --- 8
--   | \   | \   |
--   |   \ |   \ |
--   3 --- 4 --- 5
--   b1    b2    b3
--   | \   | \   |
--   |   \ |   \ |
--   0 --- 1 --- 2
--   a1    a2    a3
--
-- 1 - 3 - 0  (a2, b1, a1)
-- 1 - 4 - 3  (a2, b2, b1)
-- ...
local function floor(rows, cols)
  -- Vertex buffer (list of coordinates).
  local vb = four.Buffer { dim = 3,
             scalar_type = four.Buffer.FLOAT } 
  -- Color buffer (colors for each coordinate).
  local cb = four.Buffer { dim = 4,
             scalar_type = four.Buffer.FLOAT }
  -- Index buffer (actual triangles defined with vertices in `vb`).
  local ib = four.Buffer { dim = 1,
             scalar_type = four.Buffer.UNSIGNED_INT }
  -- Texture with original coordinate in plane
  local tex = four.Buffer { dim = 2,
             scalar_type = four.Buffer.FLOAT }

  local x_min, x_max = -1, 1
  local dx  = (x_max - x_min) / cols
  local tdx = 1 / cols
  local y_min, y_max = -1, 1
  local dy = (y_max - y_min) / rows
  local tdy = 1 / rows

  -- Create (rows+1) x (cols+1) points
  for j = 0, rows do
    local y  = y_min + dy * j
    local ty = 1.0 - tdy * j
    for i = 0, cols do
      local x  = x_min + dx * i
      -- Mirror webcam
      local tx = 1-tdx * i
      vb:push3D(x, y, 0.0)
      cb:push4D(
        math.random(),
        math.random(), 
        math.random(), 
        1.0)
      --cb:push3D(1.0, 1.0, 1.0)
      tex:push2D(tx, ty)
    end
  end


  local col_d = cols + 1
  -- Create tessels
  -- 1 - 3 - 0  (a2, b1, a1)
  -- 1 - 4 - 3  (a2, b2, b1)
  for j = 0, rows-1 do
    for i = 1, cols do
      local a2 = j * col_d + i
      local a1 = a2 - 1
      local b2 = a2 + col_d
      local b1 = b2 - 1
      ib:push3D(a2, b1, a1)
      ib:push3D(a2, b2, b1)
    end
  end

  local geom = four.Geometry {
    primitive = four.Geometry.TRIANGLE, 
    index = ib,
    data = { vertex = vb, color = cb, tex = tex}
  }
  return geom
end

-- We must now prepare the geometry that we want to display. In this example,
-- we simply create two triangles that fill the clip space (= screen).
local function square()
  -- Vertex buffer (list of coordinates).
  local vb = four.Buffer { dim = 3,
             scalar_type = four.Buffer.FLOAT } 
  -- Color buffer (colors for each coordinate).
  local cb = four.Buffer { dim = 4,
             scalar_type = four.Buffer.FLOAT }
  -- Index buffer (actual triangles defined with vertices in `vb`).
  local ib = four.Buffer { dim = 1,
             scalar_type = four.Buffer.UNSIGNED_INT }

  local tex = four.Buffer { dim = 2,
             scalar_type = four.Buffer.FLOAT }
  -- The drawing shows the coordinates and index values that we will use
  -- when filling the index.
  --
  --   #txt ascii
  --   (-1, 1)              (1, 1)
  --     +--------------------+
  --     | 2                3 |
  --     |                    |
  --     |                    |
  --     | 0                1 |
  --     +--------------------+
  --   (-1,-1)              (1, -1)
  --
  -- Create four vertices, one for each corner.
  vb:push3D(-1.0, -1.0, 0.0)
  tex:push2D(1.0, 1.0)

  vb:push3D( 1.0, -1.0, 0.0)
  tex:push2D(0.0, 1.0)

  vb:push3D(-1.0,  1.0, 0.0)
  tex:push2D(1.0, 0.0)

  vb:push3D( 1.0,  1.0, 0.0)
  tex:push2D(0.0, 0.0)

  -- Colors for the positions above.
  cb:pushV4(four.Color.red())
  cb:pushV4(four.Color.green())
  cb:pushV4(four.Color.blue())
  cb:pushV4(four.Color.white())

  -- Create two triangles made of 3 vertices. Note that the index is
  -- zero based.
  ib:push3D(0, 1, 2)
  ib:push3D(1, 3, 2)

  -- Create the actual geometry object with four.Geometry. Set the primitive
  -- to triangles and set index and data with the buffered we just prepared.
  return four.Geometry {
    primitive = four.Geometry.TRIANGLE, 
    index = ib,
    data = { vertex = vb, color = cb, tex = tex}
  }

  -- End of the local `square()` function definition.
end

webcam = webcam or video.Camera()

local      V3,      V4,      Texture,      Quat,      Transform, Camera,      Effect     =
      four.V3, four.V4, four.Texture, four.Quat, four.Transform, four.Camera, four.Effect
function texture(val)
  local data = four.Buffer {
    scalar_type = four.Buffer.UNSIGNED_BYTE,
    cdata = function() return webcam:frameData() end,
    csize = function() return webcam:frameSize() end,
  }
  
  return Texture { type = Texture.TYPE_2D, 
                   internal_format = Texture.BGRA_8UN,  --RGB_8UN,
                   size = V3(1280, 720, 1),
                   wrap_s = Texture.WRAP_CLAMP_TO_EDGE,
                   wrap_t = Texture.WRAP_CLAMP_TO_EDGE,
                   mag_filter = Texture.MAG_LINEAR,
                   min_filter = Texture.MIN_LINEAR_MIPMAP_LINEAR,
                   generate_mipmaps = true, 
                   data = data }
end


-- # Renderer
--
-- Create the renderer with four.Renderer.
renderer = renderer or four.Renderer {
  size = four.V2(WIN_SIZE.w, WIN_SIZE.h),
}

-- # Camera
--
-- Use four.Camera to create a simple camera.
camera = Camera { 
  transform = Transform { pos = V3(0, 0, 2.5) },
  background = {
    depth = 1.0,
    color = V4(0,0,0,1),
  },
}
                                                

camera2 = Camera { 
  transform = camera.transform,
  background = {
    depth = 1.0,
    color = V4(1,0,0,0.2),
  },
}

-- # Effect
--
-- We create a new four.Effect that will process our geometry and make
-- something nice out of it.
--
-- `default_uniforms` declares the uniforms and sets default values in case
-- the renderable (in our case `obj`) does not redefine these values.
--
-- The special value [RENDER_FRAME_START_TIME](four.Effect.html#RENDER_FRAME_START_TIME) set for `time` will
-- give use the current time in seconds (0 = script start).
effect = effect or four.Effect() --.Wireframe()
effect.default_uniforms.saturation = 0.5
effect.default_uniforms.time = four.Effect.RENDER_FRAME_START_TIME
effect.default_uniforms.model_to_clip = Effect.MODEL_TO_CLIP

wire = wire or Effect.Wireframe()
wire.default_uniforms.saturation = 0.5
wire.default_uniforms.time = four.Effect.RENDER_FRAME_START_TIME
wire.default_uniforms.model_to_clip = Effect.MODEL_TO_CLIP

if true then

-- Define the vertex shader. This shader simply passes values along to the
-- fragment shader.
vertex = four.Effect.Shader [[
  uniform float time;
  uniform sampler2D textfoo;
  uniform mat4 model_to_clip;
  
  in vec4 vertex;
  in vec4 color;
  in vec2 tex;

  out VertexData {
    vec4 position;
    vec2 texCoord;
  } Vertex;

  float t = time;
  float h = 0.03;

  void main()
  {
    vec4 foo = texture(textfoo, tex);
    vec4 v   = vec4(vertex.x, vertex.y, foo.r * foo.g * foo.b / 8, 1.0);

    Vertex.position = model_to_clip * v;
    Vertex.texCoord = tex;
  }
]]

local geom_shader = four.Effect.Shader [[
  layout(triangles) in;
  layout (triangle_strip, max_vertices=3) out;
   
  in VertexData {
    vec4 position;
    vec2 texCoord;
  } VertexIn[3];
   
  out VertexData {
    vec4 position;
    vec2 texCoord;
    vec3 normal;
  } VertexOut;
   
   void main()
  {
    vec3 normal = cross(
      VertexIn[1].position.xyz - 
      VertexIn[0].position.xyz,
      VertexIn[2].position.xyz -
      VertexIn[0].position.xyz
    );
        
    for(int i = 0; i < 3; i++)
    {
      gl_Position        = VertexIn[i].position;

      // copy attributes
      VertexOut.position = VertexIn[i].position;
      VertexOut.normal   = normal;
      VertexOut.texCoord = VertexIn[i].texCoord;
   
      // done with the vertex
      EmitVertex();
    }
  }
]]

effect.vertex = vertex
effect.geometry = geom_shader
wire.vertex = vertex
  
-- Define the fragment shader. This shader simply creates periodic colors
-- based on pixel position and time.
effect.fragment = four.Effect.Shader [[
  uniform float saturation;
  uniform float time;
  uniform sampler2D textfoo;

  in VertexData {
    vec4 position;
    vec2 texCoord;
    vec3 normal;
  } Vertex;

  out vec4 colorOut;

  float t = time / 3;
  float sat = saturation * 0.8 * (0.5 + 0.5 * sin(t/10));
  vec3  l_dir = normalize(vec3(0.5 * cos(t/10),0.5 * sin(t/10),0.2));

  vec4 diffuse  = vec4(0.3,0.3,0,1);
  vec4 ambient  = vec4(0.1,0.1,0.2,1);
  vec4 specular = vec4(0.8,1,1,1);
  float shininess = 0.9999;

  void main() {
 
    // set the specular term to black
    vec4 spec = vec4(0.0);
 
    // normalize both input vectors
    vec3 n = normalize(Vertex.normal);
    vec3 e = normalize(vec3(Vertex.position));
 
    float intensity = max(dot(n,l_dir), 0.0);
 

    float loc = sin((Vertex.texCoord.x * sin(t/25+sin(Vertex.texCoord.y*Vertex.texCoord.x)*2)) * 60) +
                sin((Vertex.texCoord.y * sin(t/25+sin(Vertex.texCoord.y*Vertex.texCoord.x)*2)) * 60);
    //loc = loc * loc * loc;
    loc = max(loc / 10, pow(loc, 2 + 2 * sin(t/10)));
    float m = 0.9 * sin(t/5);

    vec4 foo = texture(textfoo, Vertex.texCoord);

    // if the vertex is lit compute the specular color
    if (intensity > 0.0) {
        // compute the half vector
        vec3 h = normalize(l_dir + e);  
        // compute the specular term into spec
        float intSpec = max(dot(h,n), 0.0);
        spec = specular * pow(intSpec,shininess);
    }
    vec4 color = max(intensity *  diffuse + spec, ambient);
    colorOut = vec4(
      (0.3 *color.r + foo.r) * ((1-m) + m * sin(loc * 4)),
      (0.3 *color.g + foo.g) * ((1-m) + m * sin((t+loc)*4)),
      (0.3 *color.b + foo.b) * ((1-m) + m * sin((2*t+loc*8))),
      1.0);
  }
]]

end

-- # Renderable
--
-- Create a simple renderable object. In four, a renderable is a table that
-- contains enough information to be rendered.
--
-- The @saturation@ parameter is a uniform declaration. The value of this
-- variable will be accessible in the shader (see #Effect above).
-- 
-- We set the geometry to the fullscreen square by calling our function and
-- assign our simple effect.
obj = obj or {
  saturation = SATURATION,
  geometry   = floor(8,1),
  effect     = effect,
  textfoo    = texture(),
}

obj2 = obj or {
  saturation = SATURATION,
  geometry   = floor(8,1),
  effect     = wire,
  textfoo    = texture(),
}

local angle = -1
obj.transform = Transform { rot = Quat.rotZYX(V3(angle, 0, 0)), pos = V3(0,0,0) }
obj.effect = effect
obj.geometry  = floor(100,100)
obj2.transform = obj.transform
obj2.geometry = obj.geometry
wire.default_uniforms.wire_only = true
wire.default_uniforms.wire_color = four.V4(1,0,0,1)

local last1 = lens.elapsed()
function webcam:newFrame()
  local now = lens.elapsed()
  -- print(math.floor((now - last1) * 1000 + 0.5))
  last1 = now
  obj.textfoo = texture()
  --win:draw()
end

webcam:start()

-- # Window
--
-- We create an OpenGL window with lui.View, set the size and position.
if not win then
  win = lui.View()
  win:resize(WIN_SIZE.w, WIN_SIZE.h)
  win:move(WIN_POS.x, WIN_POS.y)
end

-- We then setup some simple keyboard actions to toggle fullscreen with
-- the space bar.
--
-- Only react to key press (press = true).
function win:keyboard(key, press)
  if key == mimas.Key_Space and press then
    win:swapFullscreen()
  end
end

function win:mouseDown()
  self:swapFullscreen()
end


-- In case we resize the window, we want our content to scale so we need to
-- update the renderer's `size` attribute.
function win:resized(w, h)
  renderer.size = four.V2(w, h)
--  self:draw()
end

obj2 = {
}
-- The window's draw function calls four.Renderer.render with our camera
-- and object and then swaps OpenGL buffers.
function win:draw()
  obj.effect = effect
  renderer:render(camera, {obj})
  --renderer:render(camera2, {obj2})
  self:swapBuffers()
end


-- Show the window once all the the callbacks are in place.
win:show()

renderer:logInfo()

-- # Runtime

-- ## Timer
-- Since our effect is a function of time, we update at 60 Hz. For this we
-- create a timer to update window content every few milliseconds.
--
-- We also change the uniform's saturation with a random value between
-- [0, 0.8] for a stupid blink effect.
timer = timer or lens.Timer(200)

local last2 = lens.elapsed()
function timer:timeout()
  local now = lens.elapsed()
  --print(math.floor((now - last2) * 1000 + 0.5))
  last2 = now
  win:draw()
  obj.saturation = math.random() * 0.8
end
timer:setInterval(1/60)

-- Start the timer.
if not timer:running() then
  timer:start(1)
end


--[[
  ## Download source

  [LiveShaderCoding.lua](example/lui/LiveShader.lua)
--]]

--halt_timer = lens.Thread(function()
--  lens.sleep(8)
--  lens.halt()
--end)


