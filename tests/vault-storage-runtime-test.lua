local SCRIPT_PATH = "repo/scripts/vault-storage/startup.lua"
local TEST_DONE = "__VAULT_RUNTIME_TEST_DONE__"

local width = 100
local height = 30
local cursorX = 1
local cursorY = 1
local screen = {}

local monitor = {}

function monitor.getTextScale()
  return 0.5
end

function monitor.setTextScale()
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

function inventory.size()
  return 50
end

function inventory.list()
  return {
    [1] = { name = "minecraft:iron_ingot", count = 1500 },
  }
end

function inventory.getItemLimit()
  return 64
end

local objects = {
  monitor_0 = monitor,
  ["create:item_vault_0"] = inventory,
}

local fakePeripheral = {}

function fakePeripheral.getNames()
  return { "monitor_0", "create:item_vault_0" }
end

function fakePeripheral.hasType(name, wanted)
  return (name == "monitor_0" and wanted == "monitor")
    or (name == "create:item_vault_0" and wanted == "inventory")
end

function fakePeripheral.wrap(name)
  return objects[name]
end

function fakePeripheral.getType(name)
  if name == "monitor_0" then
    return "monitor"
  elseif name == "create:item_vault_0" then
    return "inventory"
  end
end

function fakePeripheral.call(name, method, ...)
  return objects[name][method](...)
end

local originalPeripheral = _G.peripheral
local originalStartTimer = os.startTimer
local originalPullEvent = os.pullEvent
local eventCount = 0

_G.peripheral = fakePeripheral
os.startTimer = function()
  return 1
end
os.pullEvent = function()
  eventCount = eventCount + 1
  if eventCount == 1 then
    return "monitor_touch", "monitor_0", 14, height
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
assertContains("[1,500]", "long count after touch")
assertContains("[V01]", "vault number box")
assertContains("[ 47%]", "vault fill box")

print("PASS renders dashboard and handles SHORT/LONG touch")
os.shutdown()
