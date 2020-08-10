local Downtown = include('lib/libdowntown')

local g = grid.connect()

local DEBUG = false

local downtown = Downtown {grid = g}

g.key = function(x, y, z)
  downtown:grid_key(x, y, z)
end

function redraw()
  downtown:redraw()
end

function enc(n, d)
  downtown:enc(n, d)
end

function key(n, z)
  downtown:key(n, z)
  if DEBUG then
    if z == 1 then
      downtown:tick {}
      redraw()
    end
  end
end

function init()
  downtown:init()
  if not DEBUG then
    clock.run(
      function()
        clock.sync(4) -- try to start our bars on the Link bar start
        clock.run(
          function()
            downtown:beat()
          end
        )
      end
    )
  end
end
