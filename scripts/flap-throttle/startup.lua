local throttleSides = { "back", "bottom" }
local preferredGearshiftName = nil

local neutralLow = 7
local neutralHigh = 8
local degreesPerLevel = 3
local pollSeconds = 0.1
local stateFile = "flap_state.txt"

local function hasType(name, wanted)
  if peripheral.hasType then
    return peripheral.hasType(name, wanted)
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

local function findGearshift()
  if preferredGearshiftName and hasMethods(preferredGearshiftName, { "rotate", "isRunning" }) then
    return preferredGearshiftName, peripheral.wrap(preferredGearshiftName)
  end

  for _, name in ipairs(peripheral.getNames()) do
    if hasMethods(name, { "rotate", "isRunning" }) then
      return name, peripheral.wrap(name)
    end
  end
end

local function findMonitor()
  for _, name in ipairs(peripheral.getNames()) do
    if hasType(name, "monitor") then
      return name, peripheral.wrap(name)
    end
  end
end

local function loadCurrentAngle()
  if not fs.exists(stateFile) then
    return 0
  end

  local handle = fs.open(stateFile, "r")
  local value = tonumber(handle.readAll())
  handle.close()

  return value or 0
end

local function saveCurrentAngle(angle)
  local handle = fs.open(stateFile, "w")
  handle.write(tostring(angle))
  handle.close()
end

local function levelToTargetAngle(level)
  if level >= neutralLow and level <= neutralHigh then
    return 0
  elseif level > neutralHigh then
    return (level - neutralHigh) * degreesPerLevel
  else
    return -(neutralLow - level) * degreesPerLevel
  end
end

local function readThrottleLevel()
  local bestLevel = -1
  local bestSide = throttleSides[1]

  for _, side in ipairs(throttleSides) do
    local level = redstone.getAnalogInput(side)
    if level > bestLevel then
      bestLevel = level
      bestSide = side
    end
  end

  return bestLevel, bestSide
end

local function formatDegrees(angle)
  if angle > 0 then
    return "+" .. angle .. " deg"
  elseif angle < 0 then
    return tostring(angle) .. " deg"
  end

  return "0 deg"
end

local function centerWrite(display, y, text, textColor, backgroundColor)
  local width = display.getSize()
  display.setTextColor(textColor or colors.white)
  display.setBackgroundColor(backgroundColor or colors.black)
  display.setCursorPos(math.max(1, math.floor((width - #text) / 2) + 1), y)
  display.write(text)
end

local function drawMonitor(display, level, sourceSide, targetAngle, currentAngle, message)
  if not display then
    return
  end

  display.setTextScale(0.5)
  local width, height = display.getSize()
  display.setBackgroundColor(colors.black)
  display.clear()

  centerWrite(display, 1, "FLAPS", colors.yellow, colors.black)

  centerWrite(display, 3, "POWER LEVEL", colors.lightGray, colors.black)
  centerWrite(display, 4, tostring(level) .. " / 15", colors.white, colors.black)
  centerWrite(display, 5, "FROM " .. string.upper(sourceSide), colors.gray, colors.black)

  centerWrite(display, 7, "DEGREES", colors.lightGray, colors.black)
  centerWrite(display, 8, formatDegrees(targetAngle), colors.lime, colors.black)

  if height >= 10 then
    centerWrite(display, 10, "CURRENT " .. formatDegrees(currentAngle), colors.gray, colors.black)
  end

  if height >= 12 and message then
    display.setCursorPos(1, height)
    display.setTextColor(colors.cyan)
    display.setBackgroundColor(colors.black)
    display.clearLine()
    display.write(string.sub(message, 1, width))
  end
end

local gearshiftName, gearshift = findGearshift()
if not gearshift then
  error("No Sequenced Gearshift found. Attach it with a wired modem/network cable or place it next to the computer.")
end

local monitorName, monitor = findMonitor()
local currentAngle = loadCurrentAngle()

term.clear()
term.setCursorPos(1, 1)
print("Flap controller")
print("Gearshift: " .. gearshiftName)
print("Throttle sides: " .. table.concat(throttleSides, ", "))
print("Monitor: " .. (monitorName or "none"))
print("Saved angle: " .. currentAngle)
print("Neutral: redstone 7 or 8")

while true do
  if not monitor then
    monitorName, monitor = findMonitor()
  end

  local level, sourceSide = readThrottleLevel()
  local targetAngle = levelToTargetAngle(level)
  local message = "Ready"

  term.setCursorPos(1, 8)
  term.clearLine()
  print("Level: " .. level .. " Side: " .. sourceSide .. " Target: " .. targetAngle .. " Current: " .. currentAngle .. "   ")

  if targetAngle ~= currentAngle and not gearshift.isRunning() then
    local delta = targetAngle - currentAngle
    local angle = math.abs(delta)
    local modifier = delta > 0 and 1 or -1

    message = "Rotating " .. delta .. " deg"
    drawMonitor(monitor, level, sourceSide, targetAngle, currentAngle, message)

    term.clearLine()
    print(message .. "   ")

    gearshift.rotate(angle, modifier)

    while gearshift.isRunning() do
      drawMonitor(monitor, level, sourceSide, targetAngle, currentAngle, message)
      sleep(0.05)
    end

    currentAngle = targetAngle
    saveCurrentAngle(currentAngle)
    message = "Ready"
  end

  drawMonitor(monitor, level, sourceSide, targetAngle, currentAngle, message)
  sleep(pollSeconds)
end
