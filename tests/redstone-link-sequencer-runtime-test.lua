local SCRIPT_PATH = "scripts/redstone-link-sequencer/startup.lua"
local TEST_DONE = "__REDSTONE_LINK_SEQUENCER_RUNTIME_DONE__"

local width = 15
local height = 24
local screen = {}

local function assertEqual(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 0)
  end
end

local function makeMonitor()
  local state = {
    cursorX = 1,
    cursorY = 1,
    background = 32768,
    scale = 0.5,
  }

  local monitor = {}

  function monitor.setTextScale(scale)
    state.scale = scale
  end

  function monitor.setCursorBlink()
  end

  function monitor.getSize()
    return width, height
  end

  function monitor.setCursorPos(x, y)
    state.cursorX = x
    state.cursorY = y
  end

  function monitor.setTextColor()
  end

  function monitor.setBackgroundColor(color)
    state.background = color
  end

  function monitor.clear()
    screen = {}
  end

  function monitor.write(text)
    screen[state.cursorY] = screen[state.cursorY] or {}
    for index = 1, #text do
      local x = state.cursorX + index - 1
      if x >= 1 and x <= width and state.cursorY >= 1 and state.cursorY <= height then
        screen[state.cursorY][x] = string.sub(text, index, index)
      end
    end
    state.cursorX = state.cursorX + #text
  end

  return monitor, state
end

local function lineAt(y)
  local characters = {}
  for x = 1, width do
    characters[x] = screen[y] and screen[y][x] or " "
  end
  return table.concat(characters)
end

local function findOnMonitor(text, minimumY)
  for y = minimumY or 1, height do
    local x = string.find(lineAt(y), text, 1, true)
    if x then
      return x, y
    end
  end
end

local monitor, monitorState = makeMonitor()
local sentSignals = {}
local activeTimer = nil
local cancelledTimers = {}
local nextTimer = 100

local bridge = {}

function bridge.sendLinkSignal(firstFrequency, secondFrequency, strength)
  sentSignals[#sentSignals + 1] = {
    firstFrequency = firstFrequency,
    secondFrequency = secondFrequency,
    strength = strength,
  }
end

local fakePeripheral = {}

function fakePeripheral.getNames()
  return { "bridge", "top" }
end

function fakePeripheral.hasType(name, wanted)
  return name == "top" and wanted == "monitor"
end

function fakePeripheral.getType(name)
  if name == "top" then
    return "monitor"
  end
end

function fakePeripheral.getMethods(name)
  if name == "bridge" then
    return { "sendLinkSignal" }
  end
end

function fakePeripheral.wrap(name)
  if name == "top" then
    return monitor
  elseif name == "bridge" then
    return bridge
  end
end

local function assertLastStrengths(expected, label)
  assertEqual(#sentSignals >= 4, true, label .. " sent four signals")
  local first = #sentSignals - 3
  for index, expectedStrength in ipairs(expected) do
    assertEqual(sentSignals[first + index - 1].strength, expectedStrength, label .. " strength " .. index)
  end
end

local originalPeripheral = _G.peripheral
local originalTerm = _G.term
local originalPrint = _G.print
local originalSleep = _G.sleep
local originalColors = _G.colors
local originalPullEvent = os.pullEvent
local originalStartTimer = os.startTimer
local originalCancelTimer = os.cancelTimer

_G.peripheral = fakePeripheral
_G.term = {
  clear = function()
  end,
  setCursorPos = function()
  end,
}
_G.print = function()
end
_G.sleep = function()
  error("legacy terminal loop ran instead of the breaker panel", 0)
end
_G.colors = {
  white = 1,
  orange = 2,
  yellow = 4,
  lime = 32,
  red = 16384,
  brown = 4096,
  gray = 128,
  lightGray = 256,
  black = 32768,
}

os.startTimer = function()
  activeTimer = nextTimer
  nextTimer = nextTimer + 1
  return activeTimer
end

os.cancelTimer = function(timer)
  cancelledTimers[timer] = true
end

local eventCount = 0
os.pullEvent = function()
  eventCount = eventCount + 1

  if eventCount == 1 then
    assertEqual(monitorState.scale, 0.5, "panel monitor scale")
    if not findOnMonitor("BACKROOMS") or not findOnMonitor("MAIN SERVICE") then
      error("breaker-panel header was not rendered", 0)
    end
    if not findOnMonitor("OUTPUT: LOCKED") then
      error("panel must start with its sequence locked", 0)
    end
    assertLastStrengths({ 0, 0, 0, 0 }, "startup disconnect")
    local x, y = findOnMonitor("MAIN SERVICE")
    return "monitor_touch", "top", x, y
  elseif eventCount == 2 then
    if not findOnMonitor("CONNECTED") then
      error("main service did not turn on", 0)
    end
    local x, y = findOnMonitor("/A1\\")
    return "monitor_touch", "top", x, y
  elseif eventCount == 3 then
    local x, y = findOnMonitor("\\A2/")
    return "monitor_touch", "top", x, y
  elseif eventCount == 4 then
    local x, y = findOnMonitor("<A3>")
    return "monitor_touch", "top", x, y
  elseif eventCount == 5 then
    local x, y = findOnMonitor("[A4]")
    return "monitor_touch", "top", x, y
  elseif eventCount == 6 then
    if not findOnMonitor("OUTPUT: LIVE") then
      error("four armed red switches did not unlock the sequence", 0)
    end
    assertLastStrengths({ 15, 0, 0, 0 }, "link 1")
    return "timer", activeTimer
  elseif eventCount == 7 then
    assertLastStrengths({ 0, 15, 0, 0 }, "link 2")
    local x, y = findOnMonitor("MAIN SERVICE")
    return "monitor_touch", "top", x, y
  elseif eventCount == 8 then
    assertLastStrengths({ 0, 0, 0, 0 }, "main service disconnect")
    assertEqual(cancelledTimers[activeTimer], true, "main service cancels active sequence timer")
    error(TEST_DONE, 0)
  end

  error("Unexpected panel event", 0)
end

local ok, err = pcall(dofile, SCRIPT_PATH)

_G.peripheral = originalPeripheral
_G.term = originalTerm
_G.print = originalPrint
_G.sleep = originalSleep
_G.colors = originalColors
os.pullEvent = originalPullEvent
os.startTimer = originalStartTimer
os.cancelTimer = originalCancelTimer

if ok or not string.find(tostring(err), TEST_DONE, 1, true) then
  error("Breaker-panel runtime failed before completing its interlock test: " .. tostring(err), 0)
end

print("PASS renders the breaker panel and gates the sequence behind four red arms")
if os.shutdown then
  os.shutdown()
end
