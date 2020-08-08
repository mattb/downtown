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
    controlspec = ControlSpec.new(0, 35, 'lin', 1, 0, '')
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

function Stage:gate_mode_index()
  return params:get(self.param_prefix .. 'gate_mode')
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

  self.scale_names = {}
  for index, value in ipairs(MusicUtil.SCALES) do
    table.insert(self.scale_names, value['name'])
  end

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
    id = 'crow_reset',
    name = 'Crow reset in',
    options = {'1', '2', 'Off'},
    default = 5,
    action = function(v)
      self:setup_crow()
    end
  }

  self.stages = {}
  for i = 1, 8 do
    local stage = Stage({param_prefix = 'stage_' .. i .. '_', index = i})
    stage:setup_params()
    table.insert(self.stages, stage)
  end

  self.current_pulse = 0
  self.current_stage = 1
  self.current_note = 0
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
  if RESET_NEXT then
    self.reset_requested = true
  else
    self:perform_reset()
  end
end

function Downtown:perform_reset()
  self.current_stage = 1
  self.current_pulse = 1
end

function Downtown:tick()
  local stage = self.stages[self.current_stage]
  self.current_pulse = self.current_pulse + 1

  if self.current_pulse > stage:pulse_count() then
    self.current_pulse = 1
    local safety = 8
    repeat
      self.current_stage = self.current_stage + 1
      if self.current_stage > params:get('stages') then
        self.current_stage = 1
      end
      stage = self.stages[self.current_stage]
      safety = safety - 1
    until stage:should_skip() == false or safety == 0
  end

  if self.reset_requested then
    self.reset_requested = false
    self:perform_reset()
    stage = self.stages[self.current_stage]
  end

  local scale = self.scale_names[params:get('scale')]
  self.current_note = stage:pitch(0, scale, params:get('octaves'))
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
  screen.text('Stage ' .. self.current_stage)
  screen.move(10, 20)
  screen.text('Pulse ' .. self.current_pulse)
  screen.move(10, 30)
  screen.text('Note ' .. self.current_note)
  screen.move(10, 40)
  screen.text(self.status)
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
  if self.current_grid_key_x > 0 and self.current_grid_key_y > 0 then
    g:led(self.current_grid_key_x, self.current_grid_key_y, 15)
  end
  g:refresh()
end

function Downtown:enc(n, d)
end

function Downtown:key(n, z)
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

return Downtown
