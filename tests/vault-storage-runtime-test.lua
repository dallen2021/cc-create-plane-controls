local SCRIPT_PATH = "repo/scripts/vault-storage/startup.lua"
local TEST_DONE = "__VAULT_RUNTIME_TEST_DONE__"

local width = 100
local height = 30
local currentScale = 0.5
local cursorX = 1
local cursorY = 1
local screen = {}
local backgrounds = {}
local currentBackground = colors.black
local clearCalls = 0

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
  backgrounds = {}
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

function monitor.setBackgroundColor(color)
  currentBackground = color
end

function monitor.clear()
  clearCalls = clearCalls + 1
  screen = {}
  backgrounds = {}
  for y = 1, height do
    backgrounds[y] = {}
    for x = 1, width do
      backgrounds[y][x] = currentBackground
    end
  end
end

function monitor.write(text)
  screen[cursorY] = screen[cursorY] or {}
  for index = 1, #text do
    local x = cursorX + index - 1
    if x >= 1 and x <= width and cursorY >= 1 and cursorY <= height then
      screen[cursorY][x] = string.sub(text, index, index)
      backgrounds[cursorY] = backgrounds[cursorY] or {}
      backgrounds[cursorY][x] = currentBackground
    end
  end
  cursorX = cursorX + #text
end

local inventory = {}
local listCalls = 0
local limitCalls = 0

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
  limitCalls = limitCalls + 1
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

local function findOnScreen(text, fromBottom)
  local firstY = fromBottom and height or 1
  local lastY = fromBottom and 1 or height
  local step = fromBottom and -1 or 1

  for y = firstY, lastY, step do
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
    local x, y = findOnScreen("SHORT", true)
    if not x then
      error("SHORT button not rendered", 0)
    end
    return "monitor_touch", "monitor_0", x, y
  elseif eventCount == 2 then
    local x, y = findOnScreen("REFRESH")
    if not x then
      error("REFRESH button not rendered", 0)
    end
    return "monitor_touch", "monitor_0", x, y
  elseif eventCount == 3 then
    local x, y = findOnScreen("FONT: 0.5")
    if not x then
      error("FONT: 0.5 control not rendered", 0)
    end
    return "monitor_touch", "monitor_0", x + #"FONT: 0.5" + 1, y
  elseif eventCount == 4 then
    local x, y = findOnScreen("FONT: 1")
    if not x then
      error("FONT: 1 control not rendered after increase", 0)
    end
    return "monitor_touch", "monitor_0", x - 2, y
  elseif eventCount == 5 then
    return "timer", 1
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

local function assertNotContains(text, label)
  if string.find(rendered, text, 1, true) then
    error("Unexpected " .. label .. " in rendered dashboard: " .. text, 0)
  end
end

assertContains("STORAGE NETWORK", "dashboard title")
assertContains("Iron Ingot", "friendly item name")
assertContains("1,600", "refreshed long count")
assertNotContains("[1,600]", "bracketed item count")
assertContains("[1]", "vault number box")
assertNotContains("[V01]", "old vault number format")
assertContains("1 VAULTS", "filtered vault count")
assertContains("FONT: 0.5", "font stepper after decrease")

local refreshX, refreshY = findOnScreen("REFRESH")
local fontX, fontY = findOnScreen("FONT: 0.5")
local pageX, pageY = findOnScreen("1-1/1")
local totalX, totalY = findOnScreen("TOTAL")
if not refreshX or not fontX or not pageX or not totalX then
  error("Missing controls while checking panel layout", 0)
end

local rightWidth = math.max(24, math.floor(width * 0.35))
rightWidth = math.min(rightWidth, math.max(18, width - 30))
local dividerX = width - rightWidth
local leftX2 = dividerX - 1
local rightX1 = dividerX + 1

if refreshY ~= height or pageY ~= height or fontY ~= height then
  error("Navigation, pagination, and font controls must use the single footer row", 0)
end
if pageX + #"1-1/1" - 1 > leftX2 or pageX + #"1-1/1" - 1 < leftX2 - 1 then
  error("Pagination must be right-aligned inside the left panel", 0)
end
if fontX < rightX1 or fontX > rightX1 + 6 then
  error("Font controls must be left-aligned inside the right panel", 0)
end
if totalY ~= height - 1 or totalX < rightX1 then
  error("Total vault fill must sit at the black bottom of the right panel", 0)
end
if backgrounds[height][1] ~= colors.gray or backgrounds[height - 1][1] ~= colors.black then
  error("The gray footer must be exactly one row tall", 0)
end
if backgrounds[totalY][totalX] ~= colors.black then
  error("Total vault fill must use the black panel background", 0)
end

if listCalls ~= 3 then
  error("Expected exactly three inventory scans, got " .. listCalls, 0)
end

if limitCalls ~= 1 then
  error("Expected one capacity limit call, got " .. limitCalls, 0)
end

if currentScale ~= 0.5 then
  error("Expected font scale 0.5 after plus/minus touches, got " .. currentScale, 0)
end

if clearCalls ~= 5 then
  error("Expected unchanged timer refresh to skip redraw; clear count was " .. clearCalls, 0)
end

print("PASS renders requested labels and optimized refresh/font controls")
os.shutdown()
