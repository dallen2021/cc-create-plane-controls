local preferredGearshiftName = "Create_SequencedGearshift_0"

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

local function findMonitor()
  for _, name in ipairs(peripheral.getNames()) do
    if hasType(name, "monitor") then
      return name, peripheral.wrap(name)
    end
  end
end

local function findGearshift()
  if hasMethods(preferredGearshiftName, { "rotate", "isRunning" }) then
    return preferredGearshiftName, peripheral.wrap(preferredGearshiftName)
  end

  for _, name in ipairs(peripheral.getNames()) do
    if hasMethods(name, { "rotate", "isRunning" }) then
      return name, peripheral.wrap(name)
    end
  end
end

local monitorName, monitor = findMonitor()
if not monitor then
  error("No monitor found. Attach an Advanced Monitor to this computer or its wired network.")
end

local gearshiftName, gearshift = findGearshift()
if not gearshift then
  error("No Sequenced Gearshift found. Attach it with powered-on wired modems and networking cable.")
end

monitor.setTextScale(0.5)
monitor.setCursorBlink(false)

local buttons = {
  { label = "-90", angle = 90, modifier = -1 },
  { label = "+90", angle = 90, modifier = 1 },
  { label = "-180", angle = 180, modifier = -1 },
  { label = "+180", angle = 180, modifier = 1 },
}

local buttonAreas = {}
local status = "Ready"

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

local function drawButton(area, active)
  local bg = active and colors.orange or colors.gray
  fill(area.x1, area.y1, area.x2, area.y2, bg)

  local x = area.x1 + math.floor((area.x2 - area.x1 + 1 - #area.label) / 2)
  local y = area.y1 + math.floor((area.y2 - area.y1) / 2)
  monitor.setCursorPos(x, y)
  monitor.setTextColor(colors.white)
  monitor.setBackgroundColor(bg)
  monitor.write(area.label)
end

local function layoutButtons()
  local width, height = monitor.getSize()
  local top = 4
  local bottom = math.max(top + 1, height - 2)
  local gap = 1
  local buttonWidth = math.max(5, math.floor((width - 3 * gap) / 2))
  local buttonHeight = math.max(2, math.floor((bottom - top - gap + 1) / 2))
  local leftX = 1
  local rightX = math.min(width - buttonWidth + 1, leftX + buttonWidth + gap)

  buttonAreas = {
    { x1 = leftX, y1 = top, x2 = leftX + buttonWidth - 1, y2 = top + buttonHeight - 1, label = buttons[1].label, angle = buttons[1].angle, modifier = buttons[1].modifier },
    { x1 = rightX, y1 = top, x2 = rightX + buttonWidth - 1, y2 = top + buttonHeight - 1, label = buttons[2].label, angle = buttons[2].angle, modifier = buttons[2].modifier },
    { x1 = leftX, y1 = top + buttonHeight + gap, x2 = leftX + buttonWidth - 1, y2 = top + 2 * buttonHeight + gap - 1, label = buttons[3].label, angle = buttons[3].angle, modifier = buttons[3].modifier },
    { x1 = rightX, y1 = top + buttonHeight + gap, x2 = rightX + buttonWidth - 1, y2 = top + 2 * buttonHeight + gap - 1, label = buttons[4].label, angle = buttons[4].angle, modifier = buttons[4].modifier },
  }
end

local function draw(activeLabel)
  local width, height = monitor.getSize()
  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  monitor.clear()

  centerWrite(1, "Bearing Control", colors.yellow, colors.black)
  centerWrite(2, gearshiftName, colors.lightGray, colors.black)

  layoutButtons()
  for _, area in ipairs(buttonAreas) do
    drawButton(area, area.label == activeLabel)
  end

  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.lime)
  monitor.setCursorPos(1, height)
  monitor.clearLine()
  monitor.write(string.sub(status, 1, width))
end

local function isInside(area, x, y)
  return x >= area.x1 and x <= area.x2 and y >= area.y1 and y <= area.y2
end

local function rotate(area)
  if gearshift.isRunning() then
    status = "Busy"
    draw(area.label)
    return
  end

  status = "Rotating " .. area.label
  draw(area.label)
  gearshift.rotate(area.angle, area.modifier)

  while gearshift.isRunning() do
    sleep(0.1)
  end

  status = "Ready"
  draw()
end

draw()

while true do
  local event, side, x, y = os.pullEvent()

  if event == "monitor_touch" and side == monitorName then
    for _, area in ipairs(buttonAreas) do
      if isInside(area, x, y) then
        rotate(area)
        break
      end
    end
  elseif event == "monitor_resize" then
    draw()
  elseif event == "peripheral" or event == "peripheral_detach" then
    monitorName, monitor = findMonitor()
    gearshiftName, gearshift = findGearshift()
    if monitor and gearshift then
      status = "Ready"
      draw()
    end
  end
end
