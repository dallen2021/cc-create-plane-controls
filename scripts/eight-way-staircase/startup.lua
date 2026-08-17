local defaultHeading = "sw"
local stateFile = "eight_way_staircase_state.txt"
local pollSeconds = 0.05
local startDelaySeconds = 0.2
local deployerChannel = { "minecraft:diamond", "minecraft:emerald" }
local deployerIdleStrength = 15
local deployerReleaseSeconds = 0.9

local buttonChannels = {
  north = { "minecraft:compass", "minecraft:redstone" },
  ne = { "minecraft:redstone", "minecraft:gold_ingot" },
  east = { "minecraft:compass", "minecraft:gold_ingot" },
  se = { "minecraft:lapis_lazuli", "minecraft:gold_ingot" },
  south = { "minecraft:compass", "minecraft:lapis_lazuli" },
  sw = { "minecraft:lapis_lazuli", "minecraft:iron_ingot" },
  west = { "minecraft:compass", "minecraft:iron_ingot" },
  nw = { "minecraft:redstone", "minecraft:iron_ingot" },
  entrance = { "minecraft:emerald", "minecraft:emerald" },
}

local buttonOrder = {
  "north",
  "ne",
  "east",
  "se",
  "south",
  "sw",
  "west",
  "nw",
  "entrance",
}

local Controller = {}
Controller.buttonChannels = buttonChannels
Controller.buttonOrder = buttonOrder
Controller.defaultHeading = defaultHeading
Controller.deployerChannel = deployerChannel
Controller.deployerIdleStrength = deployerIdleStrength
Controller.deployerReleaseSeconds = deployerReleaseSeconds

local headings = {
  north = 0,
  ne = 1,
  east = 2,
  se = 3,
  south = 4,
  sw = 5,
  west = 6,
  nw = 7,
}

local diagonalHeadings = {
  ne = true,
  se = true,
  sw = true,
  nw = true,
}

function Controller.isDiagonalHeading(heading)
  return diagonalHeadings[heading] == true
end

function Controller.planDeployerClicks(currentHeading, targetHeading)
  if currentHeading == targetHeading or not Controller.isDiagonalHeading(targetHeading) then
    return {}
  end

  return { "place" }
end

function Controller.resolveButtonTarget(button, currentHeading)
  if button == "entrance" then
    if currentHeading == "sw" then
      return "south"
    end

    return "sw"
  end

  return button
end

function Controller.resolveTurn(current, target)
  local currentIndex = headings[current]
  local targetIndex = headings[target]

  if currentIndex == nil then
    error("Unknown current heading: " .. tostring(current))
  end

  if targetIndex == nil then
    error("Unknown target heading: " .. tostring(target))
  end

  local difference = (targetIndex - currentIndex) % 8

  if difference == 0 then
    return { angle = 0, modifier = 0 }
  end

  if difference == 4 then
    return { angle = 180, modifier = 1 }
  end

  if difference < 4 then
    return { angle = difference * 45, modifier = -1 }
  end

  return { angle = (8 - difference) * 45, modifier = 1 }
end

function Controller.selectActiveButton(activeButtons, newlyPressedButtons, currentHeading)
  if #activeButtons > 1 then
    local labels = {}
    for _, button in ipairs(activeButtons) do
      labels[#labels + 1] = string.upper(button)
    end

    return {
      target = nil,
      message = "Conflicting signals: " .. table.concat(labels, " + "),
    }
  end

  if #newlyPressedButtons == 1 then
    local button = newlyPressedButtons[1]
    return {
      target = Controller.resolveButtonTarget(button, currentHeading),
      message = "Last input: " .. string.upper(button),
    }
  end

  return {
    target = nil,
    message = nil,
  }
end

if rawget(_G, "__EIGHT_WAY_STAIRCASE_TEST") then
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
local lastConflictMessage = nil

local function drawStatus(message)
  term.clear()
  term.setCursorPos(1, 1)
  print("Eight-Way Staircase")
  print("Heading: " .. string.upper(currentHeading))
  print("45-degree controller")
  print("Bridge: " .. bridgeName)
  print("Gearshift: " .. gearshiftName)
  print("")
  print(message or "Ready")
end

local function isPressed(channel)
  return bridge.getLinkSignal(channel[1], channel[2]) > 0
end

local function setDeployerLinkStrength(strength)
  bridge.sendLinkSignal(deployerChannel[1], deployerChannel[2], strength)
end

local function clickBearing(action)
  local actionLabel = action == "assemble" and "Assembling" or "Placing"
  drawStatus(actionLabel .. " at " .. string.upper(currentHeading))

  setDeployerLinkStrength(0)

  local waited, waitError = pcall(function()
    sleep(deployerReleaseSeconds)
  end)

  local restored, restoreError = pcall(function()
    setDeployerLinkStrength(deployerIdleStrength)
  end)

  if not restored then
    error("Unable to stop Deployer clutch: " .. tostring(restoreError), 0)
  end

  if not waited then
    error(waitError, 0)
  end

  sleep(startDelaySeconds)
end

local function rotateTo(target, completionMessage)
  local plan = Controller.resolveTurn(currentHeading, target)
  local deployerClicks = Controller.planDeployerClicks(currentHeading, target)

  if plan.angle == 0 then
    drawStatus((completionMessage or "Last input: " .. string.upper(target)) .. " (already facing)")
    return
  end

  if gearshift.isRunning() then
    drawStatus("Gearshift is busy; " .. (completionMessage or "input ignored"))
    return
  end

  drawStatus("Turning to " .. string.upper(target))

  local ok, err = pcall(function()
    for _, action in ipairs(deployerClicks) do
      if action == "assemble" then
        clickBearing(action)
      end
    end

    drawStatus("Turning to " .. string.upper(target))
    gearshift.rotate(plan.angle, plan.modifier)

    sleep(startDelaySeconds)
    while gearshift.isRunning() do
      sleep(pollSeconds)
    end

    for _, action in ipairs(deployerClicks) do
      if action == "place" then
        clickBearing(action)
      end
    end
  end)

  if not ok then
    setDeployerLinkStrength(deployerIdleStrength)
    drawStatus("Rotate error: " .. tostring(err) .. "; " .. (completionMessage or "input ignored"))
    return
  end

  currentHeading = target
  saveHeading(currentHeading)
  drawStatus(completionMessage or "Ready")
end

setDeployerLinkStrength(deployerIdleStrength)
drawStatus("Ready")

while true do
  local activeButtons = {}
  local newlyPressedButtons = {}

  for _, button in ipairs(buttonOrder) do
    local channel = buttonChannels[button]
    local pressed = isPressed(channel)

    if pressed then
      activeButtons[#activeButtons + 1] = button
    end

    if pressed and not heldButtons[button] then
      newlyPressedButtons[#newlyPressedButtons + 1] = button
    end

    heldButtons[button] = pressed
  end

  local command = Controller.selectActiveButton(activeButtons, newlyPressedButtons, currentHeading)
  if command.target then
    lastConflictMessage = nil
    rotateTo(command.target, command.message)
  elseif command.message then
    if command.message ~= lastConflictMessage then
      drawStatus(command.message)
    end

    lastConflictMessage = command.message
  else
    lastConflictMessage = nil
  end

  sleep(pollSeconds)
end
