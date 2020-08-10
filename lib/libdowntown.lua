local Object = include('lib/object')
local inspect = include('lib/inspect')
local MusicUtil = require 'musicutil'
local ControlSpec = require 'controlspec'

local RESET_NEXT = false -- don't perform reset until next tick
local GATE_MODES = {
  'Repeat',
  'Hold',
  'Single',
  'Rest'
}

-- STAGE --

local Stage = Object:extend()

function Stage:new(options)
  self.param_prefix = options.param_prefix
  self.index = options.index
end

function Stage:setup_params()
  params:add_group('STAGE ' .. self.index, 4)
  params:add {
    type = 'control',
    id = self.param_prefix .. 'note',
    name = 'Note',
    controlspec = ControlSpec.new(0, 36, 'lin', 1, 0, ''),
    action = function()
      screen.ping()
    end
  }

  params:add {
    type = 'control',
    id = self.param_prefix .. 'pulse_count',
    name = 'Pulse count',
    controlspec = ControlSpec.new(1, 8, 'lin', 1, 1, '')
  }

  params:add {
    type = 'option',
    id = self.param_prefix .. 'gate_mode',
    name = 'Pulse count',
    options = GATE_MODES
  }

  params:add {
    type = 'option',
    id = self.param_prefix .. 'slide',
    name = 'Slide',
    options = {'No', 'Yes', 'Skip'}
  }
end

function Stage:set_gate_mode_index(i)
  return params:set(self.param_prefix .. 'gate_mode', i)
end

function Stage:inc_gate_mode_index(inc)
  local i = params:get(self.param_prefix .. 'gate_mode')
  if inc >= 1 then
    i = i + 1
  end
  if inc <= -1 then
    i = i - 1
  end
  if i > 4 then
    i = 1
  end
  if i < 1 then
    i = 4
  end
  params:set(self.param_prefix .. 'gate_mode', i)
end

function Stage:gate_mode_index()
  return params:get(self.param_prefix .. 'gate_mode')
end

function Stage:gate_mode_code()
  local name = params:string(self.param_prefix .. 'gate_mode')
  if name == 'Rest' then
    return '..'
  end
  return string.sub(name, 1, 1)
end

function Stage:rotate_skip_slide()
  local i = params:get(self.param_prefix .. 'slide')
  i = i + 1
  if i > 3 then
    i = 1
  end
  params:set(self.param_prefix .. 'slide', i)
end

function Stage:should_slide()
  return (params:get(self.param_prefix .. 'slide') == 2)
end

function Stage:should_hold()
  return (params:get(self.param_prefix .. 'gate_mode') == 2)
end

function Stage:should_rest(pulse)
  if params:get(self.param_prefix .. 'gate_mode') == 1 then --  Repeat
    return false
  end
  if params:get(self.param_prefix .. 'gate_mode') == 2 then -- Hold
    return false
  end
  if params:get(self.param_prefix .. 'gate_mode') == 3 then -- Single
    return (pulse > 1)
  end
  if params:get(self.param_prefix .. 'gate_mode') == 4 then -- Rest
    return true
  end
end

function Stage:should_skip()
  return (params:get(self.param_prefix .. 'slide') == 3)
end

function Stage:set_pulse_count(c)
  return params:set(self.param_prefix .. 'pulse_count', c)
end

function Stage:pulse_count()
  return params:get(self.param_prefix .. 'pulse_count')
end

function Stage:note_param(octaves)
  local n = params:get(self.param_prefix .. 'note')
  return n / 3.0 * octaves
end

function Stage:inc_note(delta)
  local n = params:get(self.param_prefix .. 'note') + delta
  if n > 36 then
    n = 36
  end
  if n < 0 then
    n = 0
  end
  params:set(self.param_prefix .. 'note', n)
  print(n)
end

function Stage:pitch(root, scale, octaves)
  notes = MusicUtil.generate_scale(root, scale, octaves)
  return MusicUtil.snap_note_to_array(self:note_param(octaves) + root, notes)
end

-- DOWNTOWN --

local Downtown = Object:extend()

function Downtown:new(options)
  Downtown.super.new(self)
  self.grid = options.grid
  self.current_grid_key_x = 0
  self.current_grid_key_y = 0
  self.reset_requested = false
  self.status = ''
  self.last_tick = clock.get_beats()
  self.pingpong_inc = 1
  self.ui = {
    current_note = 1
  }

  self.scale_names = {}
  for index, value in ipairs(MusicUtil.SCALES) do
    table.insert(self.scale_names, value['name'])
  end

  self:setup_params()

  self:do_reset()
  self.current_note = 0
end

function Downtown:setup_params()
  params:add_separator('DOWNTOWN')

  params:add {
    type = 'option',
    id = 'scale',
    name = 'Scale',
    options = self.scale_names
  }

  params:add {
    type = 'control',
    id = 'octaves',
    name = 'Octaves',
    controlspec = ControlSpec.new(1, 3, 'lin', 1, 3, '')
  }

  params:add {
    type = 'control',
    id = 'stages',
    name = 'Stages',
    controlspec = ControlSpec.new(1, 8, 'lin', 1, 8, '')
  }

  params:add {
    type = 'control',
    id = 'gate_time',
    name = 'Gate time',
    controlspec = ControlSpec.new(0, 1, 'lin', 0.01, 0.06, '')
  }

  params:add {
    type = 'control',
    id = 'slide_time',
    name = 'Slide time',
    controlspec = ControlSpec.new(0, 1, 'lin', 0.01, 0.06, '')
  }

  params:add {
    type = 'option',
    id = 'direction_mode',
    name = 'Direction mode',
    options = {'Forward', 'Reverse', 'Pingpong', 'Brownian', 'Random'}
  }

  params:add {
    type = 'option',
    id = 'fixed_mode',
    name = 'Fixed mode',
    options = {'Off', 'On'},
    action = function(val)
      self.pulse_countdown = 0
    end
  }

  self.clock_divider = 1
  params:add {
    type = 'option',
    id = 'clock_divider',
    name = 'Clock divider',
    options = {
      '1/32',
      '1/16',
      '1/12',
      '1/8',
      '1/6',
      '1/4',
      '1/3',
      '1/2',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '12',
      '16',
      '24',
      '32',
      '48',
      '64'
    },
    default = 9,
    action = function(v)
      self.clock_divider = load('return ' .. params:string('clock_divider'))()
    end
  }

  params:add {
    type = 'option',
    id = 'crow_reset',
    name = 'Crow reset in',
    options = {'1', '2', 'Off'},
    default = 3,
    action = function(v)
      self:setup_crow()
    end
  }

  params:add {
    type = 'number',
    id = 'reset_beat_count',
    name = 'Reset on beat',
    default = 0,
    min = 0,
    max = 128
  }

  self.stages = {}
  for i = 1, 8 do
    local stage = Stage({param_prefix = 'stage_' .. i .. '_', index = i})
    stage:setup_params()
    table.insert(self.stages, stage)
  end
end

function Downtown:setup_crow()
  local crow_reset_in = params:get('crow_reset')
  crow.input[1].change = function()
  end
  crow.input[2].change = function()
  end
  if crow_reset_in < 3 then
    crow.input[crow_reset_in].change = function()
      self:reset()
    end
    crow.input[crow_reset_in].mode('change', 2.0, 0.25, 'rising')
  end
end

function Downtown:reset()
  local now = clock.get_beats()
  print('RESET signalled at ' .. now - self.last_tick .. ' since last tick')
  print('Last tick was at beat ' .. math.floor((self.last_tick * 4) % 4))
  print('Reset signal was at beat ' .. math.floor((now * 4) % 4))
  print(' ---')
  if RESET_NEXT then
    self.reset_requested = true
  else
    self:do_reset()
    self:tick {skip_advance = true}
  end
end

function Downtown:do_reset()
  self.current_stage = 0
  if params:string('fixed_mode') == 'On' then
    self.pulse_countdown = params:get('stages')
  end
  self:goto_next_stage()
end

function Downtown:goto_next_stage()
  local old_stage = self.current_stage
  self.current_pulse = 1
  local safety = 8
  local stage
  local direction = params:string('direction_mode')
  local inc = 1
  if direction == 'Reverse' then
    inc = -1
  end
  if direction == 'Brownian' then
    local i = math.random(100)
    if i <= 25 then
      inc = -1
    elseif i <= 50 then
      inc = 0
    end
  end
  if direction == 'Pingpong' then
    inc = self.pingpong_inc
  end
  repeat
    if direction == 'Random' then
      self.current_stage = math.random(params:get('stages'))
    else
      self.current_stage = self.current_stage + inc
    end
    if self.current_stage > params:get('stages') then
      if direction == 'Pingpong' then
        if params:get('stages') == 1 then
          self.current_stage = 1
        else
          self.current_stage = params:get('stages') - 1
        end
      else
        self.current_stage = 1
      end
      self.pingpong_inc = -1
    end
    if self.current_stage < 1 then
      if direction == 'Pingpong' then
        if params:get('stages') == 1 then
          self.current_stage = 1
        else
          self.current_stage = 2
        end
      else
        self.current_stage = params:get('stages')
      end
      self.pingpong_inc = 1
    end
    safety = safety - 1
    stage = self.stages[self.current_stage]
  until stage:should_skip() == false or safety == 0
end

function Downtown:calculate_next()
  local reset_beat_count = params:get('reset_beat_count')
  if reset_beat_count > 0 then
    local beat = math.floor((clock.get_beats() * 4) % reset_beat_count)
    if beat == 0 then
      self:do_reset()
      return
    end
  end

  if self.reset_requested then
    self.reset_requested = false
    self:do_reset()
    return
  end

  local stage = self.stages[self.current_stage]
  self.current_pulse = self.current_pulse + 1
  if params:string('fixed_mode') == 'On' then
    if self.pulse_countdown <= 0 then
      self:do_reset()
    end
    self.pulse_countdown = self.pulse_countdown - 1
  end
  if self.current_pulse > stage:pulse_count() then
    self:goto_next_stage()
  end
end

function Downtown:tick(options)
  self.last_tick = clock.get_beats()
  self:calculate_next()

  local stage = self.stages[self.current_stage]

  if not options.skip_advance then
    if stage:should_rest(self.current_pulse) then
      crow.output[1].volts = 0
      self.status = 'REST  '
    else
      local gate_time = params:get('gate_time')
      if stage:should_hold() then
        gate_time = 10
        self.status = 'HOLD  '
      else
        self.status = 'PULSE '
      end
      crow.output[1].action = 'pulse(' .. gate_time .. ', 5, 1)'
      crow.output[1]()
    end
  end

  local scale = self.scale_names[params:get('scale')]
  self.current_note = stage:pitch(0, scale, params:get('octaves'))
  crow.output[2].volts = self.current_note / 12.0
  if stage:should_slide() then
    crow.output[2].slew = params:get('slide_time')
    self.status = self.status .. 'SLIDE '
  else
    crow.output[2].slew = 0
  end
  self:update_grid()
end

function Downtown:redraw()
  screen.clear()
  screen.level(15)
  screen.move(10, 10)
  screen.font_face(1)
  screen.font_size(8)
  screen.text(MusicUtil.note_num_to_name(self.current_note + 24, true))

  screen.level(8)
  for i = 1, self.current_stage do
    screen.rect(5 + i * 5, 20, 3, 3)
    screen.stroke()
  end
  for i = 1, self.current_pulse do
    screen.rect(5 + i * 5, 25, 3, 3)
    screen.stroke()
  end

  local x = 64 - 7
  for i = 1, 8 do
    if self.ui.current_note == i then
      screen.level(15)
      screen.rect(x + i * 7 + 1, 6, 2, 2)
      screen.stroke()
    end
    screen.level(3)
    if self.current_stage == i then
      screen.level(8)
    end
    if i > params:get('stages') then
      screen.level(1)
    end
    screen.rect(x + i * 7, 10, 4, 40)
    screen.stroke()
    screen.level(12)
    screen.move(x + i * 7 + 2, 48)
    local octaves = params:get('octaves')
    local note = self.stages[i]:note_param(octaves)
    screen.line(x + i * 7 + 2, 47 - (note * (octaves / 3)))
    screen.stroke()

    local nn = MusicUtil.note_num_to_name(note + 24, false)
    screen.move(x + i * 7, 57)
    screen.font_face(2)
    screen.font_size(7)
    screen.text(self.stages[i]:gate_mode_code())
  end

  screen.update()
end

function Downtown:update_grid()
  local g = self.grid
  for x = 1, 8 do
    for y = 1, 8 do
      local b = 8
      if y > self.stages[x]:pulse_count() then
        b = 3
      end
      if x == self.current_stage and y == self.current_pulse then
        b = 15
      end
      g:led(x, 9 - y, b)
    end

    for y = 1, 4 do
      local b = 3
      if y == self.stages[x]:gate_mode_index() then
        b = 8
      end
      g:led(x + 8, 5 - y, b)
    end

    local skip_slide = 6
    if self.stages[x]:should_skip() then
      skip_slide = 0
    end
    if self.stages[x]:should_slide() then
      skip_slide = 12
    end
    g:led(x + 8, 8, skip_slide)

    local stage_count_b = 8
    if x > params:get('stages') then
      stage_count_b = 3
    end
    g:led(x + 8, 6, stage_count_b)
  end

  for x = 1, 5 do
    g:led(x + 11, 5, 3)
    if params:get('direction_mode') == x then
      g:led(x + 11, 5, 12)
    end
  end
  if params:string('fixed_mode') == 'On' then
    g:led(9, 5, 12)
  else
    g:led(9, 5, 3)
  end

  if self.current_grid_key_x > 0 and self.current_grid_key_y > 0 then
    g:led(self.current_grid_key_x, self.current_grid_key_y, 15)
  end
  g:refresh()
end

function Downtown:enc(n, d)
  if n == 2 then
    local stage = self.stages[self.ui.current_note]
    stage:inc_gate_mode_index(d)
  end
  if n == 3 then
    local stage = self.stages[self.ui.current_note]
    stage:inc_note(d)
  end
end

function Downtown:key(n, z)
  if z == 1 and n == 2 then
    self.ui.current_note = self.ui.current_note - 1
    if self.ui.current_note == 0 then
      self.ui.current_note = 8
    end
  end
  if z == 1 and n == 3 then
    self.ui.current_note = self.ui.current_note + 1
    if self.ui.current_note == 9 then
      self.ui.current_note = 1
    end
  end
end

function Downtown:grid_key(x, y, z)
  if x <= 8 and y <= 8 and z == 1 then
    self.stages[x]:set_pulse_count(9 - y)
    self.current_grid_key_x = x
    self.current_grid_key_y = y
  end

  if x >= 9 and x <= 16 and y <= 5 and z == 1 then
    self.stages[x - 8]:set_gate_mode_index(5 - y)
    self.current_grid_key_x = x
    self.current_grid_key_y = y
  end

  if x >= 9 and x <= 16 and y == 8 and z == 1 then
    self.stages[x - 8]:rotate_skip_slide()
  end

  if x >= 9 and x <= 16 and y == 5 and z == 1 then
    if x == 9 then
      if params:string('fixed_mode') == 'On' then
        params:set('fixed_mode', 1)
      else
        params:set('fixed_mode', 2)
      end
    end
    if x >= 12 then
      params:set('direction_mode', x - 11)
    end
  end

  if x >= 9 and x <= 16 and y == 6 and z == 1 then
    params:set('stages', x - 8)
    self.current_grid_key_x = x
    self.current_grid_key_y = y
  end

  if z == 0 then
    self.current_grid_key_x = 0
    self.current_grid_key_y = 0
  end
  self:update_grid()
end

function Downtown:init()
end

function Downtown:beat()
  while true do
    clock.sync(self.clock_divider / 4)
    self:tick {}
    redraw()
  end
end

return Downtown
