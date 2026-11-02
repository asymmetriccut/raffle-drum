-- Raffle Drum
--
-- ball sequencer
-- inspired by the OP-1 tombola sequencer
-- plays MIDI notes: each note
-- becomes a ball (max 64)
-- inside a rotating shapes.
-- Plays when it hits
-- the walls
--
-- E1: shape
-- E2: gravity
-- E3: speed (rotation)
-- K1 (keep) + E2: mass
-- K2: random ball
-- K3: clear
--
-- all parameters also
-- in the PARAMS menu

engine.name = "PolyPerc"

local MusicUtil = require "musicutil"

local MAX_BALLS = 64
local CX, CY, R = 64, 32, 30
local BALL_R = 2.2
local MAX_SPEED = 300
local FRICTION = 0.25   -- attrito parete/pallina (la gabbia "trascina")
local ROT_UNIT = 0.6    -- rad/s per ogni unita' di speed
local SUBSTEPS = 4

local shapes = {
  {"triangle", 3}, {"square", 4}, {"pentagon", 5},
  {"hexagon", 6}, {"octagon", 8}, {"circle", 24}
}
local shape_names = {}
for i, s in ipairs(shapes) do shape_names[i] = s[1] end

local balls = {}
local edges, verts = {}, {}
local nsides = 6
local apothem = R
local angle = 0
local alt = false
local midi_in, midi_out
local loop_id

---------------------------------------------------------------- shape

-- ricalcola normali e vertici in base all'angolo corrente
local function update_geometry()
  for k = 0, nsides - 1 do
    -- a angle=0 un lato e' appoggiato in basso
    local phi = angle + math.pi / 2 + 2 * math.pi * k / nsides
    edges[k + 1] = {ox = math.cos(phi), oy = math.sin(phi)}
    local a = phi + math.pi / nsides
    verts[k + 1] = {CX + R * math.cos(a), CY + R * math.sin(a)}
  end
end

local function build_shape()
  nsides = shapes[params:get("shape")][2]
  apothem = R * math.cos(math.pi / nsides)
  edges, verts = {}, {}
  update_geometry()
end

---------------------------------------------------------------- suono

local function play(note, vel)
  local out = params:get("output") -- 1 internal, 2 midi, 3 both
  if out ~= 2 then
    engine.amp(vel / 127 * 0.8)
    engine.hz(MusicUtil.note_num_to_freq(note))
  end
  if out ~= 1 and midi_out then
    local ch = params:get("midi_out_ch")
    midi_out:note_on(note, vel, ch)
    clock.run(function()
      clock.sleep(params:get("note_len") / 1000)
      midi_out:note_off(note, 0, ch)
    end)
  end
end

---------------------------------------------------------------- palline

local function drop(note, vel)
  if #balls >= MAX_BALLS then table.remove(balls, 1) end
  -- le palline partono dall'alto e cadono
  balls[#balls + 1] = {
    x = CX + (math.random() - 0.5) * 16,
    y = CY - apothem * 0.55,
    vx = (math.random() - 0.5) * 30,
    vy = math.random() * 10,
    note = note,
    vel = vel,
    flash = 0
  }
end

local function step(dt)
  local omega = params:get("speed") * ROT_UNIT
  local g = params:get("gravity") * 150
  local e = 0.4 + params:get("mass") * 0.65 -- restituzione (bounciness)
  local lim = apothem - BALL_R

  angle = (angle + omega * dt) % (2 * math.pi)
  update_geometry()

  for _, b in ipairs(balls) do
    b.vy = b.vy + g * dt
    b.x = b.x + b.vx * dt
    b.y = b.y + b.vy * dt

    for _, ed in ipairs(edges) do
      local rx, ry = b.x - CX, b.y - CY
      local s = rx * ed.ox + ry * ed.oy
      if s > lim then
        -- spingi la pallina dentro
        b.x = b.x - ed.ox * (s - lim)
        b.y = b.y - ed.oy * (s - lim)
        rx, ry = b.x - CX, b.y - CY

        -- velocita' della parete in movimento nel punto di contatto
        local wvx, wvy = -omega * ry, omega * rx
        local rvx, rvy = b.vx - wvx, b.vy - wvy
        local vn = rvx * ed.ox + rvy * ed.oy

        if vn > 0 then
          local tx, ty = rvx - vn * ed.ox, rvy - vn * ed.oy
          local f = 1 - FRICTION
          rvx = tx * f - e * vn * ed.ox
          rvy = ty * f - e * vn * ed.oy
          b.vx, b.vy = rvx + wvx, rvy + wvy

          if vn > 8 then
            local v = math.floor(b.vel * (0.4 + math.min(vn / 100, 0.6)))
            play(b.note, util.clamp(v, 1, 127))
            b.flash = 1
          end
        end
      end
    end

    -- limite di velocita' (con mass alto l'energia puo' crescere)
    local sp = math.sqrt(b.vx * b.vx + b.vy * b.vy)
    if sp > MAX_SPEED then
      b.vx = b.vx / sp * MAX_SPEED
      b.vy = b.vy / sp * MAX_SPEED
    end
  end
end

local function update()
  local dt = (1 / 60) / SUBSTEPS
  for _ = 1, SUBSTEPS do step(dt) end
  for _, b in ipairs(balls) do
    b.flash = math.max(0, b.flash - 0.1)
  end
end

---------------------------------------------------------------- midi

local function midi_event(data)
  local msg = midi.to_msg(data)
  local ch = params:get("midi_in_ch")
  if ch > 0 and msg.ch ~= ch then return end
  if msg.type == "note_on" and msg.vel > 0 then
    drop(msg.note, msg.vel)
  end
end

local function connect_midi_in(v)
  if midi_in then midi_in.event = nil end
  midi_in = midi.connect(v)
  midi_in.event = midi_event
end

---------------------------------------------------------------- init

function init()
  params:add_separator("TOMBOLA")

  -- speed = velocita' di rotazione del contenitore (negativo = senso opposto)
  params:add_control("speed", "speed (rotation)", controlspec.new(-3, 3, "lin", 0, 0.8))
  params:add_control("mass", "mass (bounce)", controlspec.new(0, 1, "lin", 0.01, 0.8))
  params:add_control("gravity", "gravity", controlspec.new(-1, 1, "lin", 0.01, 0.4))
  params:add_option("shape", "shape", shape_names, 4)
  params:set_action("shape", build_shape)

  params:add_separator("OUTPUT")
  params:add_option("output", "output", {"internal", "midi", "both"}, 1)
  params:add_control("release", "release (internal)",
    controlspec.new(0.1, 3.2, "lin", 0.01, 0.5, "s"))
  params:set_action("release", function(x) engine.release(x) end)
  params:add_number("note_len", "midi note length", 10, 2000, 150, function(p) return p:get() .. " ms" end)

  params:add_separator("MIDI")
  params:add_number("midi_in_device", "midi in device", 1, 4, 1)
  params:set_action("midi_in_device", connect_midi_in)
  params:add_number("midi_in_ch", "midi in channel", 0, 16, 0,
    function(p) return p:get() == 0 and "all" or p:get() end)
  params:add_number("midi_out_device", "midi out device", 1, 4, 1)
  params:set_action("midi_out_device", function(v) midi_out = midi.connect(v) end)
  params:add_number("midi_out_ch", "midi out channel", 1, 16, 1)

  build_shape()
  connect_midi_in(params:get("midi_in_device"))
  midi_out = midi.connect(params:get("midi_out_device"))

  loop_id = clock.run(function()
    while true do
      clock.sleep(1 / 60)
      update()
      redraw()
    end
  end)
end

function cleanup()
  if loop_id then clock.cancel(loop_id) end
end

---------------------------------------------------------------- controlli

function enc(n, d)
  if n == 1 then
    params:delta("shape", d)
  elseif n == 2 then
    if alt then params:delta("mass", d) else params:delta("gravity", d) end
  elseif n == 3 then
    params:delta("speed", d)
  end
end

function key(n, z)
  if n == 1 then
    alt = (z == 1)
  elseif n == 2 and z == 1 then
    drop(48 + math.random(0, 24), 100)
  elseif n == 3 and z == 1 then
    balls = {}
  end
end

---------------------------------------------------------------- schermo

function redraw()
  screen.clear()
  screen.aa(1)

  -- contenitore che ruota
  screen.line_width(1.5)
  screen.level(12)
  for i, v in ipairs(verts) do
    if i == 1 then screen.move(v[1], v[2]) else screen.line(v[1], v[2]) end
  end
  screen.close()
  screen.stroke()

  -- palline
  screen.line_width(1)
  for _, b in ipairs(balls) do
    screen.level(math.floor(7 + 8 * b.flash))
    screen.circle(b.x, b.y, BALL_R + b.flash * 0.8)
    screen.fill()
  end

  -- valori (discreti, agli angoli)
  screen.font_size(8)
  screen.level(alt and 12 or 4)
  screen.move(0, 7)
  screen.text("spd " .. string.format("%.1f", params:get("speed")))
  screen.move(0, 16)
  screen.text("grv " .. string.format("%.2f", params:get("gravity")))
  screen.move(128, 7)
  screen.text_right("mass " .. string.format("%.2f", params:get("mass")))
  screen.move(128, 16)
  screen.text_right(shape_names[params:get("shape")])
  screen.level(3)
  screen.move(0, 63)
  screen.text(#balls .. "/" .. MAX_BALLS)

  screen.update()
end
