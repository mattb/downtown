local Object = include('lib/object')
local inspect = include('lib/inspect')
local MusicUtil = require 'musicutil'
local ControlSpec = require 'controlspec'

local Stage = Object:extend()

local GATE_MODES = {
  'Repeat',
  'Hold',
  'Single',
  'Rest'
}

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
    return (pulse == 1)
  end
  if params:get(self.param_prefix .. 'gate_mode') == 4 then -- Rest
    return true
  end
end

function Stage:should_skip()
  return (params:get(self.param_prefix .. 'slide') == 3)
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

local Downtown = Object:extend()

function Downtown:new()
  Downtown.super.new(self)

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

  local scale = self.scale_names[params:get('scale')]
  self.current_note = stage:pitch(0, scale, params:get('octaves'))
  if stage:should_rest(self.current_pulse) then
    crow.output[1].volts = 0
  else
    local gate_time = params:get('gate_time')
    if stage:should_hold() then
      gate_time = 10
    end
    crow.output[1].action = 'pulse(' .. gate_time .. ', 5, 1)'
    crow.output[1]()
  end
  crow.output[2].volts = self.current_note / 12.0
  if stage:should_slide() then
    crow.output[2].slew = params:get('slide_time')
  else
    crow.output[2].slew = 0
  end
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
  screen.update()
end

function Downtown:enc(n, d)
end

function Downtown:key(n, z)
end

function Downtown:init()
end

return Downtown
