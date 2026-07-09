local modemSide = "right"
local receiverId = 11
local protocol = "plane_landing_gear"

local function hasType(name, wanted)
  if peripheral.hasType then
    return peripheral.hasType(name, wanted)
  end

  return peripheral.getType(name) == wanted
end

local function findMonitor()
  for _, name in ipairs(peripheral.getNames()) do
    if hasType(name, "monitor") then
      return name, peripheral.wrap(name)
    end
  end
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

local monitorName, monitor = findMonitor()
if not monitor then
  error("No monitor found. Attach an Advanced Monitor to this cockpit computer.")
end

requireWirelessModem(modemSide)

monitor.setTextScale(0.5)
monitor.setCursorBlink(false)

local buttons = {
  { label = "GEAR UP", command = "up" },
  { label = "GEAR DOWN", command = "down" },
}

local buttonAreas = {}
local status = "Ready"
local lastState = "unknown"
local activeCommand = nil

local function centerWrite(y, text, fg, bg)
  local width = monitor.getSize()
  monitor.setTextColor(fg or colors.white)
  monitor.setBackgroundColor(bg or colors.black)
  monitor.setCursorPos(math.max(1, math.floor((width - #text) / 2) + 1), y)
  monitor.write(text)
end

local function fill(x1, y1, x2, y2, color)
  monitor.setBackgroundColor(color)
  for y = y1, y2 do
    monitor.setCursorPos(x1, y)
    monitor.write(string.rep(" ", math.max(0, x2 - x1 + 1)))
  end
end

local function layoutButtons()
  local width, height = monitor.getSize()
  local gap = 1
  local top = 5
  local bottom = math.max(top + 3, height - 3)
  local buttonHeight = math.max(3, math.floor((bottom - top - gap + 1) / 2))

  buttonAreas = {
    {
      x1 = 2,
      y1 = top,
      x2 = width - 1,
      y2 = top + buttonHeight - 1,
      label = buttons[1].label,
      command = buttons[1].command,
    },
    {
      x1 = 2,
      y1 = top + buttonHeight + gap,
      x2 = width - 1,
      y2 = top + 2 * buttonHeight + gap - 1,
      label = buttons[2].label,
      command = buttons[2].command,
    },
  }
end

local function drawButton(area)
  local bg = colors.gray
  if activeCommand == area.command then
    bg = colors.orange
  elseif lastState == area.command then
    bg = colors.green
  end

  fill(area.x1, area.y1, area.x2, area.y2, bg)

  local x = area.x1 + math.floor((area.x2 - area.x1 + 1 - #area.label) / 2)
  local y = area.y1 + math.floor((area.y2 - area.y1) / 2)
  monitor.setCursorPos(x, y)
  monitor.setTextColor(colors.white)
  monitor.setBackgroundColor(bg)
  monitor.write(area.label)
end

local function draw()
  local width, height = monitor.getSize()
  monitor.setBackgroundColor(colors.black)
  monitor.clear()

  centerWrite(1, "LANDING GEAR", colors.yellow, colors.black)
  centerWrite(2, "Remote computer #" .. receiverId, colors.lightGray, colors.black)
  centerWrite(3, "State: " .. string.upper(lastState), colors.lime, colors.black)

  layoutButtons()
  for _, area in ipairs(buttonAreas) do
    drawButton(area)
  end

  monitor.setCursorPos(1, height)
  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.cyan)
  monitor.clearLine()
  monitor.write(string.sub(status, 1, width))
end

local function isInside(area, x, y)
  return x >= area.x1 and x <= area.x2 and y >= area.y1 and y <= area.y2
end

local function sendGearCommand(command)
  activeCommand = command
  status = "Sending " .. string.upper(command)
  rednet.send(receiverId, command, protocol)
  draw()
end

local function handleReceiverMessage(message)
  if type(message) ~= "string" then
    return
  end

  if message == "gear_up" then
    lastState = "up"
    activeCommand = nil
    status = "Gear is UP"
  elseif message == "gear_down" then
    lastState = "down"
    activeCommand = nil
    status = "Gear is DOWN"
  elseif message == "already_up" then
    lastState = "up"
    activeCommand = nil
    status = "Already UP"
  elseif message == "already_down" then
    lastState = "down"
    activeCommand = nil
    status = "Already DOWN"
  elseif message == "moving_up" then
    status = "Moving UP"
  elseif message == "moving_down" then
    status = "Moving DOWN"
  elseif message == "busy" then
    activeCommand = nil
    status = "Receiver busy"
  elseif string.sub(message, 1, 6) == "error:" then
    activeCommand = nil
    status = message
  else
    status = "Receiver: " .. message
  end

  draw()
end

draw()
rednet.send(receiverId, "status", protocol)

while true do
  local event, a, b, c = os.pullEvent()

  if event == "monitor_touch" and a == monitorName then
    local x = b
    local y = c
    for _, area in ipairs(buttonAreas) do
      if isInside(area, x, y) then
        sendGearCommand(area.command)
        break
      end
    end
  elseif event == "monitor_resize" then
    draw()
  elseif event == "rednet_message" then
    local sender = a
    local message = b
    local messageProtocol = c
    if sender == receiverId and messageProtocol == protocol then
      handleReceiverMessage(message)
    end
  elseif event == "peripheral" or event == "peripheral_detach" then
    local newMonitorName, newMonitor = findMonitor()
    if newMonitor then
      monitorName = newMonitorName
      monitor = newMonitor
      monitor.setTextScale(0.5)
      draw()
    end
  end
end
