local onStrength = 15
local offStrength = 0
local breakerCount = 8
local armingSwitchCount = 4
local monitorTextScale = 0.5
local minimumMonitorWidth = 15
local minimumMonitorHeight = 24
local preferredMonitorName = nil

local links = {
  { "minecraft:red_sandstone", "minecraft:sandstone" },
  { "minecraft:red_sandstone", "minecraft:red_sandstone" },
  { "minecraft:sandstone", "minecraft:red_sandstone" },
  { "minecraft:sandstone", "minecraft:sandstone" },
}

local steps = {
  { activeLink = 1, seconds = 1 },
  { activeLink = 2, seconds = 1 },
  { activeLink = 3, seconds = 1 },
  { activeLink = 4, seconds = 5 },
  { activeLink = nil, seconds = 10 },
}

local Controller = {}
Controller.links = links
Controller.steps = steps
Controller.onStrength = onStrength
Controller.offStrength = offStrength

function Controller.strengthsForStep(step)
  local strengths = {}

  for index = 1, #links do
    strengths[index] = step.activeLink == index and onStrength or offStrength
  end

  return strengths
end

local function copySwitches(switches, count, defaultValue)
  local copy = {}
  for index = 1, count do
    if switches and switches[index] ~= nil then
      copy[index] = switches[index] == true
    else
      copy[index] = defaultValue
    end
  end
  return copy
end

function Controller.copyState(state)
  local current = state or {}
  return {
    mainOn = current.mainOn == true,
    leftBreakers = copySwitches(current.leftBreakers, breakerCount, true),
    rightBreakers = copySwitches(current.rightBreakers, breakerCount, true),
    armingSwitches = copySwitches(current.armingSwitches, armingSwitchCount, false),
  }
end

function Controller.newState()
  return Controller.copyState(nil)
end

function Controller.isBreakerOn(state, side, index)
  local current = Controller.copyState(state)
  local breakers = side == "left" and current.leftBreakers
    or side == "right" and current.rightBreakers

  return current.mainOn and breakers ~= nil and breakers[index] == true
end

function Controller.isArmingSwitchOn(state, index)
  local current = Controller.copyState(state)
  return current.mainOn and current.armingSwitches[index] == true
end

function Controller.isSequenceArmed(state)
  local current = Controller.copyState(state)
  if not current.mainOn then
    return false
  end

  for index = 1, armingSwitchCount do
    if not current.armingSwitches[index] then
      return false
    end
  end

  return true
end

function Controller.toggleMain(state)
  local nextState = Controller.copyState(state)
  nextState.mainOn = not nextState.mainOn
  return nextState, true, nextState.mainOn and "Main service connected" or "Main service disconnected"
end

function Controller.toggleBreaker(state, side, index)
  local nextState = Controller.copyState(state)
  if not nextState.mainOn then
    return nextState, false, "Main service is off"
  end

  local breakers = side == "left" and nextState.leftBreakers
    or side == "right" and nextState.rightBreakers
  if not breakers or index < 1 or index > breakerCount then
    return nextState, false, "Unknown breaker"
  end

  breakers[index] = not breakers[index]
  return nextState, true, string.upper(side) .. " breaker " .. index .. (breakers[index] and " on" or " off")
end

function Controller.toggleArmingSwitch(state, index)
  local nextState = Controller.copyState(state)
  if not nextState.mainOn then
    return nextState, false, "Main service is off"
  end

  if index < 1 or index > armingSwitchCount then
    return nextState, false, "Unknown arming switch"
  end

  nextState.armingSwitches[index] = not nextState.armingSwitches[index]
  return nextState, true, "Arming switch " .. index .. (nextState.armingSwitches[index] and " on" or " off")
end

if rawget(_G, "__REDSTONE_LINK_SEQUENCER_TEST") then
  return Controller
end

local function hasType(name, wanted)
  if peripheral.hasType then
    local ok, result = pcall(peripheral.hasType, name, wanted)
    if ok then
      return result
    end
  end
  return peripheral.getType(name) == wanted
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

local function findBridge()
  for _, name in ipairs(peripheral.getNames()) do
    if hasMethods(name, { "sendLinkSignal" }) then
      return name, peripheral.wrap(name)
    end
  end
end

local function findMonitor()
  local names = {}
  for _, name in ipairs(peripheral.getNames()) do
    if hasType(name, "monitor") then
      names[#names + 1] = name
    end
  end

  table.sort(names)
  if preferredMonitorName then
    for _, name in ipairs(names) do
      if name == preferredMonitorName then
        return name, peripheral.wrap(name)
      end
    end
    error("Configured monitor not found: " .. preferredMonitorName)
  end

  if #names ~= 1 then
    error("Connect exactly one monitor or set preferredMonitorName in startup.lua")
  end

  return names[1], peripheral.wrap(names[1])
end

local bridgeName, bridge = findBridge()
if not bridge then
  error("No transmitting Redstone Link Bridge found. Attach it directly or through powered wired modems.")
end

local monitorName, display = findMonitor()
if not display then
  error("Could not wrap breaker-panel monitor: " .. tostring(monitorName))
end

local function configureMonitor()
  display.setTextScale(monitorTextScale)
  display.setCursorBlink(false)

  local width, height = display.getSize()
  if width < minimumMonitorWidth or height < minimumMonitorHeight then
    error(string.format(
      "Monitor %s is too small (%dx%d); need at least %dx%d",
      monitorName,
      width,
      height,
      minimumMonitorWidth,
      minimumMonitorHeight
    ))
  end
end

local function fitText(value, width)
  local text = tostring(value or "")
  if #text <= width then
    return text
  elseif width <= 3 then
    return string.sub(text, 1, math.max(0, width))
  end
  return string.sub(text, 1, width - 3) .. "..."
end

local function fill(x1, y1, x2, y2, color)
  local width = math.max(0, x2 - x1 + 1)
  display.setBackgroundColor(color)
  for y = y1, y2 do
    display.setCursorPos(x1, y)
    display.write(string.rep(" ", width))
  end
end

local function writeAt(x, y, value, foreground, background, maximumWidth)
  local text = fitText(value, maximumWidth or #tostring(value or ""))
  display.setCursorPos(x, y)
  display.setTextColor(foreground or colors.white)
  display.setBackgroundColor(background or colors.black)
  display.write(text)
end

local function centerWrite(y, value, foreground, background)
  local width = display.getSize()
  local text = fitText(value, width)
  local x = math.max(1, math.floor((width - #text) / 2) + 1)
  writeAt(x, y, text, foreground, background, width)
end

local buttons = {}
local currentState = Controller.newState()
local currentStepIndex = 1
local sequenceTimer = nil
local statusMessage = "Turn on main service"

local function registerButton(kind, index, x1, y1, x2, y2)
  buttons[#buttons + 1] = {
    kind = kind,
    index = index,
    x1 = x1,
    y1 = y1,
    x2 = x2,
    y2 = y2,
  }
end

local function drawMainService()
  local background = currentState.mainOn and colors.lime or colors.red
  fill(2, 3, 14, 4, background)
  centerWrite(3, "MAIN SERVICE", colors.black, background)
  centerWrite(4, currentState.mainOn and "CONNECTED" or "DISCONNECT", colors.black, background)
  registerButton("main", nil, 2, 3, 14, 4)
end

local function drawBreaker(side, index, x1, y)
  local on = Controller.isBreakerOn(currentState, side, index)
  local background = on and colors.lime or colors.gray
  local label
  if side == "left" then
    label = on and "< ON " or " OFF>"
  else
    label = on and " ON >" or "<OFF "
  end

  fill(x1, y, x1 + 4, y, background)
  writeAt(x1, y, label, colors.black, background, 5)
  registerButton(side, index, x1, y, x1 + 4, y)
end

local armLayouts = {
  { x1 = 2, y1 = 16, x2 = 6, y2 = 17, label = "/A1\\" },
  { x1 = 9, y1 = 15, x2 = 13, y2 = 16, label = "\\A2/" },
  { x1 = 1, y1 = 20, x2 = 5, y2 = 21, label = "<A3>" },
  { x1 = 10, y1 = 19, x2 = 14, y2 = 20, label = "[A4]" },
}

local function drawArmingSwitch(index)
  local area = armLayouts[index]
  local on = Controller.isArmingSwitchOn(currentState, index)
  local background
  if not currentState.mainOn then
    background = colors.gray
  elseif on then
    background = colors.red
  else
    background = colors.brown
  end

  fill(area.x1, area.y1, area.x2, area.y2, background)
  local labelX = area.x1 + math.max(0, math.floor((area.x2 - area.x1 + 1 - #area.label) / 2))
  writeAt(labelX, area.y1, area.label, colors.white, background, area.x2 - area.x1 + 1)
  writeAt(area.x1 + 1, area.y2, on and "ON " or "OFF", colors.white, background, area.x2 - area.x1 - 1)
  registerButton("arm", index, area.x1, area.y1, area.x2, area.y2)
end

local function armingCount()
  local count = 0
  for index = 1, armingSwitchCount do
    if currentState.armingSwitches[index] then
      count = count + 1
    end
  end
  return count
end

local function drawPanel()
  local width, height = display.getSize()
  buttons = {}

  display.setBackgroundColor(colors.black)
  display.setTextColor(colors.white)
  display.clear()

  fill(1, 1, width, 1, colors.gray)
  centerWrite(1, "BACKROOMS", colors.yellow, colors.gray)
  centerWrite(2, "BREAKER BOX", colors.lightGray, colors.black)
  drawMainService()
  centerWrite(5, "BRANCH BREAKERS", colors.lightGray, colors.black)

  for index = 1, breakerCount do
    local y = 5 + index
    drawBreaker("left", index, 1, y)
    writeAt(6, y, string.format("%02d|%02d", index, index), colors.lightGray, colors.black, 5)
    drawBreaker("right", index, 11, y)
  end

  centerWrite(14, "RED ARM SWITCHES", colors.red, colors.black)
  for index = 1, armingSwitchCount do
    drawArmingSwitch(index)
  end

  centerWrite(22, "ARMS " .. armingCount() .. "/4", colors.lightGray, colors.black)
  centerWrite(
    23,
    Controller.isSequenceArmed(currentState) and "OUTPUT: LIVE" or "OUTPUT: LOCKED",
    Controller.isSequenceArmed(currentState) and colors.lime or colors.red,
    colors.black
  )
  centerWrite(height, statusMessage, colors.lightGray, colors.black)
end

local function drawTerminal()
  term.clear()
  term.setCursorPos(1, 1)
  print("Backrooms breaker panel")
  print("Monitor: " .. monitorName)
  print("Bridge: " .. bridgeName)
  print("Main service: " .. (currentState.mainOn and "on" or "off"))
  print("Red arms: " .. armingCount() .. "/4")
  print("Sequence: " .. (Controller.isSequenceArmed(currentState) and "live" or "locked"))
end

local function sendStep(step)
  local strengths = Controller.strengthsForStep(step)
  for index, link in ipairs(links) do
    bridge.sendLinkSignal(link[1], link[2], strengths[index])
  end
end

local function stopSequence()
  if sequenceTimer and os.cancelTimer then
    os.cancelTimer(sequenceTimer)
  end
  sequenceTimer = nil
  currentStepIndex = 1
  sendStep(steps[#steps])
end

local function runCurrentStep()
  local step = steps[currentStepIndex]
  sendStep(step)
  sequenceTimer = os.startTimer(step.seconds)
  statusMessage = step.activeLink and "Link " .. step.activeLink .. " active" or "All links off"
end

local function reconcileSequence()
  if Controller.isSequenceArmed(currentState) then
    if not sequenceTimer then
      currentStepIndex = 1
      runCurrentStep()
    end
  else
    stopSequence()
  end
end

local function isInside(button, x, y)
  return x >= button.x1 and x <= button.x2 and y >= button.y1 and y <= button.y2
end

local function handleTouch(x, y)
  local button
  for _, candidate in ipairs(buttons) do
    if isInside(candidate, x, y) then
      button = candidate
      break
    end
  end
  if not button then
    return
  end

  local nextState, changed, message
  if button.kind == "main" then
    nextState, changed, message = Controller.toggleMain(currentState)
  elseif button.kind == "left" or button.kind == "right" then
    nextState, changed, message = Controller.toggleBreaker(currentState, button.kind, button.index)
  elseif button.kind == "arm" then
    nextState, changed, message = Controller.toggleArmingSwitch(currentState, button.index)
  end

  if changed then
    currentState = nextState
  end
  statusMessage = message or statusMessage
  reconcileSequence()
  drawPanel()
  drawTerminal()
end

configureMonitor()
stopSequence()
drawPanel()
drawTerminal()

while true do
  local event, a, b, c = os.pullEvent()

  if event == "monitor_touch" and a == monitorName then
    handleTouch(b, c)
  elseif event == "monitor_resize" and a == monitorName then
    configureMonitor()
    drawPanel()
  elseif event == "timer" and a == sequenceTimer then
    currentStepIndex = currentStepIndex % #steps + 1
    sequenceTimer = nil
    runCurrentStep()
    drawPanel()
    drawTerminal()
  end
end
