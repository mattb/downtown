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

function init()
  downtown:init()
end
