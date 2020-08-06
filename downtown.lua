local Downtown = include('lib/libdowntown')

local downtown = Downtown()

function redraw()
  downtown:redraw()
end

function enc(n, d)
  downtown:enc(n, d)
end

function key(n, z)
  downtown:key(n, z)
end

local function beat()
  while true do
    clock.sync(1 / 4)
    downtown:tick()
    redraw()
  end
end

function init()
  downtown:init()
  clock.run(beat)
end
