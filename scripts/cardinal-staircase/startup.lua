local defaultHeading = "south"
local stateFile = "cardinal_staircase_state.txt"
local pollSeconds = 0.05
local startDelaySeconds = 0.2

local buttonChannels = {
  north = { "minecraft:compass", "minecraft:redstone" },
  east = { "minecraft:compass", "minecraft:gold_ingot" },
  south = { "minecraft:compass", "minecraft:lapis_lazuli" },
  west = { "minecraft:compass", "minecraft:iron_ingot" },
}

local Controller = {}
Controller.buttonChannels = buttonChannels

local headings = {
  north = 0,
  east = 1,
  south = 2,
  west = 3,
}

function Controller.resolveTurn(current, target)
  local currentIndex = headings[current]
  local targetIndex = headings[target]

  if currentIndex == nil then
    error("Unknown current heading: " .. tostring(current))
  end

  if targetIndex == nil then
    error("Unknown target heading: " .. tostring(target))
  end

  local difference = (targetIndex - currentIndex) % 4

  if difference == 0 then
    return { angle = 0, modifier = 0 }
  end

  if difference == 1 then
    return { angle = 90, modifier = 1 }
  end

  if difference == 2 then
    return { angle = 180, modifier = 1 }
  end

  return { angle = 90, modifier = -1 }
end

if rawget(_G, "__CARDINAL_STAIRCASE_TEST") then
  return Controller
end

local function hasMethods(name, required)
  local methods = peripheral.getMethods(name)
  if not methods then
    return false
  end

  local found = {}
  for _, method in ipairs(methods) do
    found[method] = true
  end

  for _, method in ipairs(required) do
    if not found[method] then
      return false
    end
  end

  return true
end

local function findPeripheral(required)
  for _, name in ipairs(peripheral.getNames()) do
    if hasMethods(name, required) then
      return name, peripheral.wrap(name)
    end
  end
end

local function loadHeading()
  if not fs.exists(stateFile) then
    return defaultHeading
  end

  local handle = fs.open(stateFile, "r")
  local saved = string.lower((handle.readAll() or ""):gsub("%s+", ""))
  handle.close()

  if headings[saved] ~= nil then
    return saved
  end

  return defaultHeading
end

local function saveHeading(heading)
  local handle = fs.open(stateFile, "w")
  handle.write(heading)
  handle.close()
end

local bridgeName, bridge = findPeripheral({ "getLinkSignal", "sendLinkSignal" })
if not bridge then
  error("No Redstone Link Bridge found. Attach it directly or through powered wired modems.")
end

local gearshiftName, gearshift = findPeripheral({ "rotate", "isRunning" })
if not gearshift then
  error("No Sequenced Gearshift found. Attach it directly or through powered wired modems.")
end

local currentHeading = loadHeading()
saveHeading(currentHeading)
local heldButtons = {}

local function drawStatus(message)
  term.clear()
  term.setCursorPos(1, 1)
  print("Cardinal Staircase")
  print("Heading: " .. string.upper(currentHeading))
  print("Bridge: " .. bridgeName)
  print("Gearshift: " .. gearshiftName)
  print("")
  print(message or "Ready")
end

local function isPressed(channel)
  return bridge.getLinkSignal(channel[1], channel[2]) > 0
end

local function rotateTo(target)
  local plan = Controller.resolveTurn(currentHeading, target)

  if plan.angle == 0 then
    drawStatus("Already facing " .. string.upper(target))
    return
  end

  if gearshift.isRunning() then
    drawStatus("Gearshift is busy")
    return
  end

  drawStatus("Turning to " .. string.upper(target))

  local ok, err = pcall(function()
    gearshift.rotate(plan.angle, plan.modifier)
  end)

  if not ok then
    drawStatus("Rotate error: " .. tostring(err))
    return
  end

  sleep(startDelaySeconds)
  while gearshift.isRunning() do
    sleep(pollSeconds)
  end

  currentHeading = target
  saveHeading(currentHeading)
  drawStatus("Ready")
end

drawStatus("Ready")

while true do
  for target, channel in pairs(buttonChannels) do
    local pressed = isPressed(channel)

    if pressed and not heldButtons[target] then
      rotateTo(target)
    end

    heldButtons[target] = pressed
  end

  sleep(pollSeconds)
end
