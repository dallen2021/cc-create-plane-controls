local SCRIPT_PATH = "scripts/dual-monitor-door/startup.lua"
local TEST_DONE = "__DUAL_MONITOR_DOOR_RUNTIME_DONE__"

local width = 29
local height = 19
local monitorStates = {}

local function makeMonitor(name)
  local state = {
    cursorX = 1,
    cursorY = 1,
    background = colors.black,
    screen = {},
    backgrounds = {},
    scale = 0.5,
  }
  monitorStates[name] = state

  local monitor = {}

  function monitor.getTextScale()
    return state.scale
  end

  function monitor.setTextScale(scale)
    state.scale = scale
  end

  function monitor.getSize()
    return width, height
  end

  function monitor.setCursorPos(x, y)
    state.cursorX = x
    state.cursorY = y
  end

  function monitor.setCursorBlink()
  end

  function monitor.setTextColor()
  end

  function monitor.setBackgroundColor(color)
    state.background = color
  end

  function monitor.clear()
    state.screen = {}
    state.backgrounds = {}
    for y = 1, height do
      state.backgrounds[y] = {}
      for x = 1, width do
        state.backgrounds[y][x] = state.background
      end
    end
  end

  function monitor.write(text)
    state.screen[state.cursorY] = state.screen[state.cursorY] or {}
    state.backgrounds[state.cursorY] = state.backgrounds[state.cursorY] or {}
    for index = 1, #text do
      local x = state.cursorX + index - 1
      if x >= 1 and x <= width and state.cursorY >= 1 and state.cursorY <= height then
        state.screen[state.cursorY][x] = string.sub(text, index, index)
        state.backgrounds[state.cursorY][x] = state.background
      end
    end
    state.cursorX = state.cursorX + #text
  end

  return monitor
end

local monitors = {
  top = makeMonitor("top"),
  bottom = makeMonitor("bottom"),
}

local function lineAt(name, y)
  local characters = {}
  local state = monitorStates[name]
  for x = 1, width do
    characters[x] = state.screen[y] and state.screen[y][x] or " "
  end
  return table.concat(characters)
end

local function findOnMonitor(name, text, minimumY)
  for y = minimumY or 1, height do
    local x = string.find(lineAt(name, y), text, 1, true)
    if x then
      return x, y, monitorStates[name].backgrounds[y][x]
    end
  end
end

local fakePeripheral = {}

function fakePeripheral.getNames()
  return { "bottom", "top" }
end

function fakePeripheral.hasType(name, wanted)
  return monitors[name] ~= nil and wanted == "monitor"
end

function fakePeripheral.getType(name)
  if monitors[name] then
    return "monitor"
  end
end

function fakePeripheral.wrap(name)
  return monitors[name]
end

local outputCalls = {}
local fakeRedstone = {}

function fakeRedstone.setAnalogOutput(side, level)
  table.insert(outputCalls, { side = side, level = level })
end

local files = {}
local fakeFs = {}
local realFs = _G.fs
setmetatable(fakeFs, { __index = realFs })

function fakeFs.exists(path)
  if path ~= "dual_monitor_door_state.txt" then
    return realFs.exists(path)
  end
  return files[path] ~= nil
end

function fakeFs.open(path, mode)
  if path ~= "dual_monitor_door_state.txt" then
    return realFs.open(path, mode)
  end

  if mode == "r" then
    if files[path] == nil then
      return nil
    end
    return {
      readAll = function()
        return files[path]
      end,
      close = function()
      end,
    }
  end

  if mode == "w" then
    local pieces = {}
    return {
      write = function(value)
        table.insert(pieces, tostring(value))
      end,
      close = function()
        files[path] = table.concat(pieces)
      end,
    }
  end
end

local originalPeripheral = _G.peripheral
local originalRedstone = _G.redstone
local originalFs = _G.fs
local originalPullEvent = os.pullEvent
local eventCount = 0

_G.peripheral = fakePeripheral
_G.redstone = fakeRedstone
_G.fs = fakeFs

os.pullEvent = function()
  eventCount = eventCount + 1

  if eventCount == 1 then
    if not findOnMonitor("top", "INSIDE DOOR") then
      error("top was not assigned as the inside panel", 0)
    end
    if not findOnMonitor("bottom", "OUTSIDE DOOR") then
      error("bottom was not assigned as the outside panel", 0)
    end
    if #outputCalls ~= 1 or outputCalls[1].side ~= "front" or outputCalls[1].level ~= 0 then
      error("startup must apply the closed signal to the front side", 0)
    end

    local x, y, background = findOnMonitor("bottom", "OPEN", 5)
    if not x or background ~= colors.green then
      error("outside OPEN must begin enabled", 0)
    end
    return "monitor_touch", "bottom", x, y
  elseif eventCount == 2 then
    if #outputCalls ~= 2 or outputCalls[2].level ~= 15 then
      error("outside OPEN did not apply the open signal", 0)
    end
    local x, y = findOnMonitor("top", "LOCK OUTSIDE", 5)
    if not x then
      error("inside lock button was not rendered", 0)
    end
    return "monitor_touch", "top", x, y
  elseif eventCount == 3 then
    if not findOnMonitor("bottom", "ACCESS: LOCKED") then
      error("outside panel did not show its locked state", 0)
    end
    local openX, _, openBackground = findOnMonitor("bottom", "OPEN", 5)
    local closeX, closeY, closeBackground = findOnMonitor("bottom", "CLOSE", 5)
    if not openX or openBackground ~= colors.gray then
      error("outside OPEN must be disabled while locked", 0)
    end
    if not closeX or closeBackground ~= colors.orange then
      error("outside CLOSE must remain enabled while the locked door is open", 0)
    end
    return "monitor_touch", "bottom", closeX, closeY
  elseif eventCount == 4 then
    if #outputCalls ~= 3 or outputCalls[3].level ~= 0 then
      error("outside CLOSE did not apply the closed signal", 0)
    end
    local x, y, background = findOnMonitor("bottom", "OPEN", 5)
    if not x or background ~= colors.gray then
      error("outside OPEN must stay disabled after closing a locked door", 0)
    end
    return "monitor_touch", "bottom", x, y
  elseif eventCount == 5 then
    if #outputCalls ~= 3 then
      error("touching disabled outside OPEN changed the door output", 0)
    end
    local x, y, background = findOnMonitor("top", "OPEN", 5)
    if not x or background ~= colors.green then
      error("inside OPEN must remain enabled while outside access is locked", 0)
    end
    return "monitor_touch", "top", x, y
  elseif eventCount == 6 then
    if #outputCalls ~= 4 or outputCalls[4].level ~= 15 then
      error("inside OPEN did not apply the open signal", 0)
    end
    local x, y = findOnMonitor("top", "UNLOCK OUTSIDE", 5)
    if not x then
      error("inside unlock button was not rendered", 0)
    end
    return "monitor_touch", "top", x, y
  elseif eventCount == 7 then
    if not findOnMonitor("bottom", "ACCESS: UNLOCKED") then
      error("outside panel did not show its unlocked state", 0)
    end
    if not files["dual_monitor_door_state.txt"] then
      error("door and lock state were not persisted", 0)
    end
  end

  error(TEST_DONE, 0)
end

_G.__DUAL_MONITOR_DOOR_TEST = nil
local ok, err = pcall(dofile, SCRIPT_PATH)

_G.peripheral = originalPeripheral
_G.redstone = originalRedstone
_G.fs = originalFs
os.pullEvent = originalPullEvent

if ok or not string.find(tostring(err), TEST_DONE, 1, true) then
  error("Dual-monitor door runtime failed before completing the interaction test: " .. tostring(err), 0)
end

print("PASS renders and enforces dual-monitor door locking")
os.shutdown()
