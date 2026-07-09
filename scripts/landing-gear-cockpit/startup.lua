local modemSide = "right"

local landingReceiverId = 11
local landingProtocol = "plane_landing_gear"
local landingMonitorName = nil
local landingMonitorSection = 2
local landingMonitorSections = 5

local cargoReceiverId = 15
local cargoProtocol = "plane_cargo_door"
local cargoMonitorName = "left"
local cargoFallbackSection = 3
local cargoFallbackSections = 5

local function hasType(name, wanted)
  if peripheral.hasType then
    return peripheral.hasType(name, wanted)
  end

  return peripheral.getType(name) == wanted
end

local function getMonitor(name)
  if name and hasType(name, "monitor") then
    return name, peripheral.wrap(name)
  end
end

local function getMonitorNames()
  local names = {}
  for _, name in ipairs(peripheral.getNames()) do
    if hasType(name, "monitor") then
      table.insert(names, name)
    end
  end

  return names
end

local function findWideMonitor()
  local preferredName, preferred = getMonitor(landingMonitorName)
  if preferred then
    return preferredName, preferred
  end

  local bestName
  local bestMonitor
  local bestWidth = -1

  for _, name in ipairs(getMonitorNames()) do
    local monitor = peripheral.wrap(name)
    monitor.setTextScale(0.5)
    local width = monitor.getSize()

    if width > bestWidth then
      bestName = name
      bestMonitor = monitor
      bestWidth = width
    end
  end

  return bestName, bestMonitor
end

local function findCargoMonitor(landingName, landingMonitor)
  local preferredName, preferred = getMonitor(cargoMonitorName)
  if preferred and preferredName ~= landingName then
    return preferredName, preferred, 1, 1
  end

  for _, name in ipairs({ "left", "top", "bottom", "front", "back", "right" }) do
    local monitorName, monitor = getMonitor(name)
    if monitor and monitorName ~= landingName then
      return monitorName, monitor, 1, 1
    end
  end

  for _, name in ipairs(getMonitorNames()) do
    if name ~= landingName then
      return name, peripheral.wrap(name), 1, 1
    end
  end

  return landingName, landingMonitor, cargoFallbackSection, cargoFallbackSections
end

local function requireWirelessModem(side)
  if not hasType(side, "modem") then
    error("No modem found on " .. side)
  end

  local modem = peripheral.wrap(side)
  if modem.isWireless and not modem.isWireless() then
    error("The modem on " .. side .. " is not wireless")
  end

  rednet.open(side)
end

local controls = {
  landing = {
    title = { "LANDING", "GEAR" },
    receiverId = landingReceiverId,
    protocol = landingProtocol,
    statePrefix = "gear",
    section = landingMonitorSection,
    sections = landingMonitorSections,
    buttons = {
      { label = "GEAR UP", command = "up" },
      { label = "GEAR DOWN", command = "down" },
    },
    state = "unknown",
    status = "Ready",
    activeCommand = nil,
    buttonAreas = {},
  },
  cargo = {
    title = { "CARGO", "DOOR" },
    receiverId = cargoReceiverId,
    protocol = cargoProtocol,
    statePrefix = "cargo",
    section = 1,
    sections = 1,
    buttons = {
      { label = "RAISE", command = "up" },
      { label = "LOWER", command = "down" },
    },
    state = "unknown",
    status = "Ready",
    activeCommand = nil,
    buttonAreas = {},
  },
}

local function getPanelBounds(display, section, sections)
  local width = display.getSize()
  local safeSections = math.max(1, sections)
  local safeSection = math.min(math.max(1, section), safeSections)
  local sectionWidth = math.max(1, math.floor(width / safeSections))
  local x1 = math.min(width, ((safeSection - 1) * sectionWidth) + 1)
  local x2 = safeSection == safeSections and width or safeSection * sectionWidth

  return x1, math.max(x1, x2)
end

local function clearPanel(display, x1, x2)
  local _, height = display.getSize()
  display.setBackgroundColor(colors.black)
  for y = 1, height do
    display.setCursorPos(x1, y)
    display.write(string.rep(" ", x2 - x1 + 1))
  end
end

local function centerWriteIn(display, x1, x2, y, text, fg, bg)
  local width = x2 - x1 + 1
  local clipped = string.sub(text, 1, width)
  display.setTextColor(fg or colors.white)
  display.setBackgroundColor(bg or colors.black)
  display.setCursorPos(x1 + math.max(0, math.floor((width - #clipped) / 2)), y)
  display.write(clipped)
end

local function fill(display, x1, y1, x2, y2, color)
  display.setBackgroundColor(color)
  for y = y1, y2 do
    display.setCursorPos(x1, y)
    display.write(string.rep(" ", math.max(0, x2 - x1 + 1)))
  end
end

local function layoutButtons(control)
  local _, height = control.monitor.getSize()
  local panelX1, panelX2 = getPanelBounds(control.monitor, control.section, control.sections)
  local gap = height >= 7 and 1 or 0
  local top = height >= 8 and 4 or 3
  local statusLine = height
  local availableHeight = math.max(2, statusLine - top)
  local buttonHeight = math.max(1, math.floor((availableHeight - gap) / 2))
  local innerX1 = math.min(panelX1 + 1, panelX2)
  local innerX2 = math.max(innerX1, panelX2 - 1)
  local firstY2 = math.min(statusLine - 1, top + buttonHeight - 1)
  local secondY1 = math.min(statusLine - 1, firstY2 + gap + 1)

  control.buttonAreas = {
    {
      x1 = innerX1,
      y1 = top,
      x2 = innerX2,
      y2 = firstY2,
      label = control.buttons[1].label,
      command = control.buttons[1].command,
    },
    {
      x1 = innerX1,
      y1 = secondY1,
      x2 = innerX2,
      y2 = math.min(statusLine - 1, secondY1 + buttonHeight - 1),
      label = control.buttons[2].label,
      command = control.buttons[2].command,
    },
  }
end

local function drawButton(control, area)
  local bg = colors.gray
  if control.activeCommand == area.command then
    bg = colors.orange
  elseif control.state == area.command then
    bg = colors.green
  end

  fill(control.monitor, area.x1, area.y1, area.x2, area.y2, bg)

  local width = area.x2 - area.x1 + 1
  local label = string.sub(area.label, 1, width)
  local x = area.x1 + math.floor((width - #label) / 2)
  local y = area.y1 + math.floor((area.y2 - area.y1) / 2)
  control.monitor.setCursorPos(x, y)
  control.monitor.setTextColor(colors.white)
  control.monitor.setBackgroundColor(bg)
  control.monitor.write(label)
end

local function drawControl(control)
  if not control.monitor then
    return
  end

  control.monitor.setTextScale(0.5)
  control.monitor.setCursorBlink(false)

  local _, height = control.monitor.getSize()
  local panelX1, panelX2 = getPanelBounds(control.monitor, control.section, control.sections)
  local panelWidth = panelX2 - panelX1 + 1
  clearPanel(control.monitor, panelX1, panelX2)

  centerWriteIn(control.monitor, panelX1, panelX2, 1, control.title[1], colors.yellow, colors.black)
  centerWriteIn(control.monitor, panelX1, panelX2, 2, control.title[2], colors.yellow, colors.black)

  if height >= 8 then
    centerWriteIn(control.monitor, panelX1, panelX2, 3, "State " .. string.upper(control.state), colors.lime, colors.black)
  end

  layoutButtons(control)
  for _, area in ipairs(control.buttonAreas) do
    drawButton(control, area)
  end

  control.monitor.setCursorPos(panelX1, height)
  control.monitor.setBackgroundColor(colors.black)
  control.monitor.setTextColor(colors.cyan)
  control.monitor.write(string.rep(" ", panelWidth))
  control.monitor.setCursorPos(panelX1, height)
  control.monitor.write(string.sub(control.status, 1, panelWidth))
end

local function drawAll()
  drawControl(controls.landing)
  drawControl(controls.cargo)
end

local function resolveMonitors()
  local landingName, landingMonitor = findWideMonitor()
  if not landingMonitor then
    error("No monitor found. Attach an Advanced Monitor to this cockpit computer.")
  end

  local cargoName, cargoMonitor, cargoSection, cargoSections = findCargoMonitor(landingName, landingMonitor)

  controls.landing.monitorName = landingName
  controls.landing.monitor = landingMonitor
  controls.landing.section = landingMonitorSection
  controls.landing.sections = landingMonitorSections

  controls.cargo.monitorName = cargoName
  controls.cargo.monitor = cargoMonitor
  controls.cargo.section = cargoSection
  controls.cargo.sections = cargoSections
end

local function isInside(area, x, y)
  return x >= area.x1 and x <= area.x2 and y >= area.y1 and y <= area.y2
end

local function sendCommand(control, command)
  control.activeCommand = command
  control.status = "Sending " .. string.upper(command)
  rednet.send(control.receiverId, command, control.protocol)
  drawControl(control)
end

local function handleReceiverMessage(control, message)
  if type(message) ~= "string" then
    return
  end

  if message == control.statePrefix .. "_up" then
    control.state = "up"
    control.activeCommand = nil
    control.status = "State UP"
  elseif message == control.statePrefix .. "_down" then
    control.state = "down"
    control.activeCommand = nil
    control.status = "State DOWN"
  elseif message == "already_up" then
    control.state = "up"
    control.activeCommand = nil
    control.status = "Already UP"
  elseif message == "already_down" then
    control.state = "down"
    control.activeCommand = nil
    control.status = "Already DOWN"
  elseif message == "moving_up" then
    control.status = "Moving UP"
  elseif message == "moving_down" then
    control.status = "Moving DOWN"
  elseif message == "busy" then
    control.activeCommand = nil
    control.status = "Receiver busy"
  elseif string.sub(message, 1, 6) == "error:" then
    control.activeCommand = nil
    control.status = message
  else
    control.status = "Receiver: " .. message
  end

  drawControl(control)
end

local function handleTouch(monitorName, x, y)
  for _, control in pairs(controls) do
    if control.monitorName == monitorName then
      for _, area in ipairs(control.buttonAreas) do
        if isInside(area, x, y) then
          sendCommand(control, area.command)
          return
        end
      end
    end
  end
end

local function handleRednet(sender, message, protocol)
  for _, control in pairs(controls) do
    if sender == control.receiverId and protocol == control.protocol then
      handleReceiverMessage(control, message)
      return
    end
  end
end

requireWirelessModem(modemSide)
resolveMonitors()
drawAll()

rednet.send(controls.landing.receiverId, "status", controls.landing.protocol)
rednet.send(controls.cargo.receiverId, "status", controls.cargo.protocol)

while true do
  local event, a, b, c = os.pullEvent()

  if event == "monitor_touch" then
    handleTouch(a, b, c)
  elseif event == "monitor_resize" then
    resolveMonitors()
    drawAll()
  elseif event == "rednet_message" then
    handleRednet(a, b, c)
  elseif event == "peripheral" or event == "peripheral_detach" then
    resolveMonitors()
    drawAll()
  end
end
