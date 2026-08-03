local insideMonitorName = "top"
local outsideMonitorName = nil
local redstoneOutputSide = "bottom"
local openSignal = 15
local closedSignal = 0
local defaultDoorState = "closed"
local defaultLocked = false
local monitorTextScale = 0.5
local minimumMonitorWidth = 18
local minimumMonitorHeight = 10
local stateFile = "dual_monitor_door_state.txt"

local Controller = {}

local function copyState(state)
  return {
    door = state and state.door == "open" and "open" or "closed",
    locked = state and state.locked == true or false,
  }
end

function Controller.isActionEnabled(state, role, action)
  local current = copyState(state)

  if action == "open" then
    return current.door == "closed" and (role == "inside" or not current.locked)
  elseif action == "close" then
    return current.door == "open"
  elseif action == "toggle_lock" then
    return role == "inside"
  end

  return false
end

function Controller.applyAction(state, role, action)
  local nextState = copyState(state)

  if action == "toggle_lock" then
    if role ~= "inside" then
      return nextState, false, "Inside panel only"
    end

    nextState.locked = not nextState.locked
    return nextState, true, nextState.locked
      and "Outside access locked"
      or "Outside access unlocked"
  elseif action == "open" then
    if nextState.door == "open" then
      return nextState, false, "Door is already open"
    elseif role == "outside" and nextState.locked then
      return nextState, false, "Outside access is locked"
    end

    nextState.door = "open"
    return nextState, true, "Opened from " .. role
  elseif action == "close" then
    if nextState.door == "closed" then
      return nextState, false, "Door is already closed"
    end

    nextState.door = "closed"
    return nextState, true, "Closed from " .. role
  end

  return nextState, false, "Unknown action"
end

function Controller.signalForDoor(doorState, openedLevel, closedLevel)
  if doorState == "open" then
    return openedLevel
  end
  return closedLevel
end

function Controller.resolveMonitorRoles(names, preferredInside, preferredOutside)
  local sorted = {}
  local present = {}
  for _, name in ipairs(names or {}) do
    if not present[name] then
      present[name] = true
      table.insert(sorted, name)
    end
  end
  table.sort(sorted)

  if preferredInside and not present[preferredInside] then
    return nil, nil, "Inside monitor not found: " .. preferredInside
  elseif preferredOutside and not present[preferredOutside] then
    return nil, nil, "Outside monitor not found: " .. preferredOutside
  elseif preferredInside and preferredInside == preferredOutside then
    return nil, nil, "Inside and outside monitors must be different"
  end

  if preferredInside and preferredOutside then
    return preferredInside, preferredOutside
  end

  if #sorted ~= 2 then
    return nil, nil, "Connect exactly two monitors or configure both monitor names"
  end

  if preferredInside then
    local outside = sorted[1] == preferredInside and sorted[2] or sorted[1]
    return preferredInside, outside
  elseif preferredOutside then
    local inside = sorted[1] == preferredOutside and sorted[2] or sorted[1]
    return inside, preferredOutside
  end

  return sorted[1], sorted[2]
end

if rawget(_G, "__DUAL_MONITOR_DOOR_TEST") then
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

local function discoverMonitorNames()
  local names = {}
  for _, name in ipairs(peripheral.getNames()) do
    if hasType(name, "monitor") then
      table.insert(names, name)
    end
  end
  return names
end

local displays = {}
local rolesByName = {}
local buttonsByName = {}
local currentState
local statusMessage = "Ready"

local function loadState()
  local fallback = {
    door = defaultDoorState == "open" and "open" or "closed",
    locked = defaultLocked == true,
  }

  if not fs.exists(stateFile) then
    return fallback
  end

  local handle = fs.open(stateFile, "r")
  if not handle then
    return fallback
  end

  local contents = handle.readAll()
  handle.close()
  local ok, saved = pcall(textutils.unserialize, contents)
  if not ok or type(saved) ~= "table" then
    return fallback
  end

  return copyState(saved)
end

local function saveState(state)
  local handle, err = fs.open(stateFile, "w")
  if not handle then
    error("Could not save door state: " .. tostring(err))
  end
  handle.write(textutils.serialize(copyState(state)))
  handle.close()
end

local function configureMonitor(name)
  local display = peripheral.wrap(name)
  if not display then
    error("Could not wrap monitor: " .. name)
  end

  display.setTextScale(monitorTextScale)
  display.setCursorBlink(false)
  local width, height = display.getSize()
  if width < minimumMonitorWidth or height < minimumMonitorHeight then
    error(string.format(
      "Monitor %s is too small (%dx%d); need at least %dx%d",
      name,
      width,
      height,
      minimumMonitorWidth,
      minimumMonitorHeight
    ))
  end
  return display
end

local function resolveDisplays()
  local insideName, outsideName, err = Controller.resolveMonitorRoles(
    discoverMonitorNames(),
    insideMonitorName,
    outsideMonitorName
  )
  if not insideName then
    error(err)
  end

  displays = {
    inside = { name = insideName, monitor = configureMonitor(insideName) },
    outside = { name = outsideName, monitor = configureMonitor(outsideName) },
  }
  rolesByName = {
    [insideName] = "inside",
    [outsideName] = "outside",
  }
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

local function fill(display, x1, y1, x2, y2, color)
  local width = math.max(0, x2 - x1 + 1)
  display.setBackgroundColor(color)
  for y = y1, y2 do
    display.setCursorPos(x1, y)
    display.write(string.rep(" ", width))
  end
end

local function writeAt(display, x, y, value, foreground, background, maximumWidth)
  local text = fitText(value, maximumWidth or #tostring(value or ""))
  display.setCursorPos(x, y)
  display.setTextColor(foreground or colors.white)
  display.setBackgroundColor(background or colors.black)
  display.write(text)
end

local function centerWrite(display, y, value, foreground, background)
  local width = display.getSize()
  local text = fitText(value, width)
  local x = math.max(1, math.floor((width - #text) / 2) + 1)
  writeAt(display, x, y, text, foreground, background, width)
end

local function drawButton(display, monitorName, action, area, label, enabled, enabledColor)
  local background = enabled and enabledColor or colors.gray
  fill(display, area.x1, area.y1, area.x2, area.y2, background)

  local width = area.x2 - area.x1 + 1
  local text = fitText(label, width)
  local x = area.x1 + math.max(0, math.floor((width - #text) / 2))
  local y = area.y1 + math.max(0, math.floor((area.y2 - area.y1) / 2))
  writeAt(display, x, y, text, colors.white, background, width)

  buttonsByName[monitorName][action] = {
    x1 = area.x1,
    y1 = area.y1,
    x2 = area.x2,
    y2 = area.y2,
  }
end

local function drawPanel(role)
  local panel = displays[role]
  local display = panel.monitor
  local monitorName = panel.name
  local width, height = display.getSize()
  buttonsByName[monitorName] = {}

  display.setBackgroundColor(colors.black)
  display.setTextColor(colors.white)
  display.clear()

  fill(display, 1, 1, width, 1, colors.gray)
  centerWrite(display, 1, string.upper(role) .. " DOOR", colors.yellow, colors.gray)
  centerWrite(
    display,
    2,
    "DOOR: " .. string.upper(currentState.door),
    currentState.door == "open" and colors.lime or colors.orange,
    colors.black
  )
  centerWrite(
    display,
    3,
    "ACCESS: " .. (currentState.locked and "LOCKED" or "UNLOCKED"),
    currentState.locked and colors.red or colors.lime,
    colors.black
  )

  local leftX = 2
  local innerWidth = width - 2
  local gap = 1
  local buttonWidth = math.max(5, math.floor((innerWidth - gap) / 2))
  local rightX = leftX + buttonWidth + gap
  local actionTop = 5
  local actionBottom

  if role == "inside" then
    local lockBottom = height - 2
    local lockTop = math.max(actionTop + 3, lockBottom - 2)
    actionBottom = lockTop - 2
    drawButton(
      display,
      monitorName,
      "toggle_lock",
      { x1 = 2, y1 = lockTop, x2 = width - 1, y2 = lockBottom },
      currentState.locked and "UNLOCK OUTSIDE" or "LOCK OUTSIDE",
      true,
      currentState.locked and colors.blue or colors.red
    )
  else
    actionBottom = height - 2
  end

  drawButton(
    display,
    monitorName,
    "open",
    { x1 = leftX, y1 = actionTop, x2 = leftX + buttonWidth - 1, y2 = actionBottom },
    "OPEN",
    Controller.isActionEnabled(currentState, role, "open"),
    colors.green
  )
  drawButton(
    display,
    monitorName,
    "close",
    { x1 = rightX, y1 = actionTop, x2 = width - 1, y2 = actionBottom },
    "CLOSE",
    Controller.isActionEnabled(currentState, role, "close"),
    colors.orange
  )

  centerWrite(display, height, statusMessage, colors.lightGray, colors.black)
end

local function drawAll()
  drawPanel("inside")
  drawPanel("outside")
end

local function drawTerminal()
  term.clear()
  term.setCursorPos(1, 1)
  print("Dual-monitor door controller")
  print("Computer ID: " .. os.getComputerID())
  print("Inside monitor: " .. displays.inside.name)
  print("Outside monitor: " .. displays.outside.name)
  print("Redstone Link side: " .. redstoneOutputSide)
  print("Door: " .. currentState.door)
  print("Outside access: " .. (currentState.locked and "locked" or "unlocked"))
end

local function applyDoorSignal(state)
  local level = Controller.signalForDoor(state.door, openSignal, closedSignal)
  redstone.setAnalogOutput(redstoneOutputSide, level)
end

local function isInside(area, x, y)
  return area and x >= area.x1 and x <= area.x2 and y >= area.y1 and y <= area.y2
end

local function handleTouch(monitorName, x, y)
  local role = rolesByName[monitorName]
  local buttons = buttonsByName[monitorName]
  if not role or not buttons then
    return
  end

  local action
  for candidate, area in pairs(buttons) do
    if isInside(area, x, y) then
      action = candidate
      break
    end
  end
  if not action then
    return
  end

  local nextState, changed, message = Controller.applyAction(currentState, role, action)
  if changed and nextState.door ~= currentState.door then
    local ok, err = pcall(applyDoorSignal, nextState)
    if not ok then
      statusMessage = "Output error: " .. tostring(err)
      drawAll()
      return
    end
  end

  if changed then
    currentState = nextState
    saveState(currentState)
  end
  statusMessage = message
  drawAll()
  drawTerminal()
end

resolveDisplays()
currentState = loadState()
applyDoorSignal(currentState)
saveState(currentState)
drawAll()
drawTerminal()

while true do
  local event, a, b, c = os.pullEvent()

  if event == "monitor_touch" then
    handleTouch(a, b, c)
  elseif event == "monitor_resize" and rolesByName[a] then
    local role = rolesByName[a]
    displays[role].monitor = configureMonitor(a)
    drawPanel(role)
  elseif event == "peripheral" or event == "peripheral_detach" then
    local ok, err = pcall(resolveDisplays)
    if ok then
      statusMessage = "Monitor network updated"
      drawAll()
      drawTerminal()
    else
      term.setCursorPos(1, 9)
      term.clearLine()
      print("Monitor error: " .. tostring(err))
    end
  end
end
