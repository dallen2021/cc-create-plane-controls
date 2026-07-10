local SCRIPT_PATH = "repo/scripts/vault-storage/startup.lua"
local TEST_DONE = "__VAULT_RUNTIME_TEST_DONE__"

local width = 100
local height = 30
local currentScale = 0.5
local cursorX = 1
local cursorY = 1
local screen = {}

local monitor = {}

function monitor.getTextScale()
  return currentScale
end

function monitor.setTextScale(scale)
  currentScale = scale
  if scale >= 1 then
    width = 60
    height = 16
  else
    width = 100
    height = 30
  end
  screen = {}
end

function monitor.getSize()
  return width, height
end

function monitor.setCursorPos(x, y)
  cursorX = x
  cursorY = y
end

function monitor.setCursorBlink()
end

function monitor.setTextColor()
end

function monitor.setBackgroundColor()
end

function monitor.clear()
  screen = {}
end

function monitor.write(text)
  screen[cursorY] = screen[cursorY] or {}
  for index = 1, #text do
    local x = cursorX + index - 1
    if x >= 1 and x <= width and cursorY >= 1 and cursorY <= height then
      screen[cursorY][x] = string.sub(text, index, index)
    end
  end
  cursorX = cursorX + #text
end

local inventory = {}
local listCalls = 0

function inventory.size()
  return 50
end

function inventory.list()
  listCalls = listCalls + 1
  return {
    [1] = { name = "minecraft:iron_ingot", count = listCalls >= 2 and 1600 or 1500 },
  }
end

function inventory.getItemLimit()
  return 64
end

local objects = {
  monitor_0 = monitor,
  ["create:item_vault_0"] = inventory,
  ["minecraft:chest_0"] = inventory,
}

local fakePeripheral = {}

function fakePeripheral.getNames()
  return { "monitor_0", "create:item_vault_0", "minecraft:chest_0" }
end

function fakePeripheral.hasType(name, wanted)
  return (name == "monitor_0" and wanted == "monitor")
    or ((name == "create:item_vault_0" or name == "minecraft:chest_0") and wanted == "inventory")
end

function fakePeripheral.wrap(name)
  return objects[name]
end

function fakePeripheral.getType(name)
  if name == "monitor_0" then
    return "monitor"
  elseif name == "create:item_vault_0" then
    return "create:item_vault", "inventory"
  elseif name == "minecraft:chest_0" then
    return "minecraft:chest", "inventory"
  end
end

function fakePeripheral.call(name, method, ...)
  return objects[name][method](...)
end

local originalPeripheral = _G.peripheral
local originalStartTimer = os.startTimer
local originalPullEvent = os.pullEvent
local eventCount = 0

local function findOnScreen(text)
  for y = 1, height do
    local characters = {}
    for x = 1, width do
      characters[x] = screen[y] and screen[y][x] or " "
    end
    local line = table.concat(characters)
    local x = string.find(line, text, 1, true)
    if x then
      return x, y
    end
  end
end

_G.peripheral = fakePeripheral
os.startTimer = function()
  return 1
end
os.pullEvent = function()
  eventCount = eventCount + 1
  if eventCount == 1 then
    return "monitor_touch", "monitor_0", 14, height
  elseif eventCount == 2 then
    local x, y = findOnScreen("REFRESH")
    if not x then
      error("REFRESH button not rendered", 0)
    end
    return "monitor_touch", "monitor_0", x, y
  elseif eventCount == 3 then
    local x, y = findOnScreen("A+")
    if not x then
      error("A+ button not rendered", 0)
    end
    return "monitor_touch", "monitor_0", x, y
  end
  error(TEST_DONE, 0)
end

_G.__VAULT_STORAGE_TEST = nil
local ok, err = pcall(dofile, SCRIPT_PATH)

_G.peripheral = originalPeripheral
os.startTimer = originalStartTimer
os.pullEvent = originalPullEvent

if ok or not string.find(tostring(err), TEST_DONE, 1, true) then
  error("Dashboard runtime failed before completing the touch test: " .. tostring(err), 0)
end

local lines = {}
for y = 1, height do
  local characters = {}
  for x = 1, width do
    characters[x] = screen[y] and screen[y][x] or " "
  end
  lines[y] = table.concat(characters)
end
local rendered = table.concat(lines, "\n")

local function assertContains(text, label)
  if not string.find(rendered, text, 1, true) then
    error("Missing " .. label .. " from rendered dashboard: " .. text, 0)
  end
end

assertContains("STORAGE NETWORK", "dashboard title")
assertContains("Iron Ingot", "friendly item name")
assertContains("[1,600]", "refreshed long count")
assertContains("[V01]", "vault number box")
assertContains("1 VAULTS", "filtered vault count")

if listCalls ~= 2 then
  error("Expected exactly two inventory scans, got " .. listCalls, 0)
end

if currentScale ~= 1 then
  error("Expected font scale 1.0 after A+ touch, got " .. currentScale, 0)
end

print("PASS filters vaults and handles mode, refresh, and font touches")
os.shutdown()
