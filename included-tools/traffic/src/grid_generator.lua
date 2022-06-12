local function gridGenerator()
  local steps = 10
  local decoded = {}
  decoded.lanes = table.chain(
    table.range(steps, -steps, function (i)
      local r = i % 2 ~= 1
      local x = (r and i * 30 - 24 or i * 30) - 30
      return { name = "L"..i, points = table.range(steps + 1, -steps - 1, 2, function (y)
        return { x, -1, (r and -y or y) * 30 + 31.5 }
      end) }
    end),
    table.range(steps, -steps, function (i)
      local r = i % 2 ~= 1
      local x = (r and i * 30 - 24 or i * 30) - 30
      return { name = "L"..i, points = table.range(steps + 1, -steps - 1, 2, function (y)
        return { (r and -y or y) * 30 + 31.5, -1, x }
      end) }
      -- return { name = "L"..i, points = { { r and -l or l, -1, x }, { r and l or -l, -1, x } } }
    end))

  decoded.intersections = table.flatten(table.range(steps, -steps, 2, function (x)
    return table.range(steps, -steps, 2, function (y)
      local px = x * 30 + 3
      local pz = y * 30 + 3
      local S = 7
      return { name = "I"..x.."_"..y, points = { { px - S, -1, pz - S }, { px + S, -1, pz - S }, { px + S, -1, pz + S }, { px - S, -1, pz + S } } }
    end)
  end))
  return decoded
end

return gridGenerator

