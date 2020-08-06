local Object = include('lib/object')

local Downtown = Object:extend()

function Downtown:new()
  Downtown.super.new(self)
end

function Downtown:redraw()
end

function Downtown:enc(n, d)
end

function Downtown:key(n, z)
end

function Downtown:init()
end

return Downtown
