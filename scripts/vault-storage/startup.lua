local preferredMonitorName = nil
local inventoryNames = {}
local textScale = 0.5
local refreshSeconds = 2
local defaultCountMode = "short"
local fallbackItemsPerSlot = 64

local Dashboard = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function round(value)
  return math.floor(value + 0.5)
end

function Dashboard.friendlyName(itemId)
  local name = tostring(itemId or "unknown")
  name = string.match(name, ":(.+)$") or name
  name = string.gsub(name, "_", " ")
  name = string.gsub(name, "(%a)([%w']*)", function(first, rest)
    return string.upper(first) .. string.lower(rest)
  end)
  return name
end

local function formatLong(value)
  local digits = tostring(math.max(0, math.floor(value or 0)))
  local formatted = digits

  while true do
    local replaced, count = string.gsub(formatted, "^(%-?%d+)(%d%d%d)", "%1,%2")
    formatted = replaced
    if count == 0 then
      return formatted
    end
  end
end

local function formatShort(value)
  local amount = math.max(0, value or 0)
  local units = {
    { divisor = 1000000000, suffix = "B" },
    { divisor = 1000000, suffix = "M" },
    { divisor = 1000, suffix = "k" },
  }

  for index, unit in ipairs(units) do
    if amount >= unit.divisor then
      while true do
        local scaled = amount / unit.divisor
        local decimals = scaled < 100 and 1 or 0
        local displayed = tonumber(string.format("%." .. decimals .. "f", scaled))

        if displayed < 1000 or index == 1 then
          return tostring(displayed) .. unit.suffix
        end

        index = index - 1
        unit = units[index]
      end
    end
  end

  return tostring(math.floor(amount))
end

function Dashboard.formatCount(value, mode)
  if mode == "long" then
    return formatLong(value)
  end
  return formatShort(value)
end

function Dashboard.makeBar(percent, width)
  local safeWidth = math.max(0, math.floor(width or 0))
  local filled = round(safeWidth * clamp(percent or 0, 0, 100) / 100)
  return string.rep("#", filled) .. string.rep("-", safeWidth - filled)
end

function Dashboard.clampOffset(offset, itemCount, visibleRows)
  local maximum = math.max(0, (itemCount or 0) - math.max(0, visibleRows or 0))
  return clamp(math.floor(offset or 0), 0, maximum)
end

function Dashboard.aggregate(snapshots, defaultItemsPerSlot)
  local itemTotals = {}
  local vaults = {}
  local totalItems = 0
  local totalCapacity = 0
  local defaultLimit = math.max(1, defaultItemsPerSlot or 64)

  for _, snapshot in ipairs(snapshots or {}) do
    local vaultItems = 0
    for _, item in pairs(snapshot.items or {}) do
      local count = math.max(0, tonumber(item.count) or 0)
      local itemId = tostring(item.name or "unknown")
      vaultItems = vaultItems + count
      itemTotals[itemId] = (itemTotals[itemId] or 0) + count
    end

    local capacity = tonumber(snapshot.capacity)
      or (math.max(0, tonumber(snapshot.size) or 0) * defaultLimit)
    local percent = capacity > 0 and clamp(round(vaultItems * 100 / capacity), 0, 100) or 0

    table.insert(vaults, {
      sourceName = tostring(snapshot.name or "unknown"),
      itemCount = vaultItems,
      capacity = capacity,
      percent = percent,
    })

    totalItems = totalItems + vaultItems
    totalCapacity = totalCapacity + capacity
  end

  table.sort(vaults, function(a, b)
    return a.sourceName < b.sourceName
  end)

  local items = {}
  for itemId, count in pairs(itemTotals) do
    table.insert(items, {
      id = itemId,
      name = Dashboard.friendlyName(itemId),
      count = count,
    })
  end

  table.sort(items, function(a, b)
    if a.count == b.count then
      if a.name == b.name then
        return a.id < b.id
      end
      return a.name < b.name
    end
    return a.count > b.count
  end)

  return {
    items = items,
    vaults = vaults,
    totalItems = totalItems,
    totalCapacity = totalCapacity,
    totalPercent = totalCapacity > 0
      and clamp(round(totalItems * 100 / totalCapacity), 0, 100)
      or 0,
  }
end

if rawget(_G, "__VAULT_STORAGE_TEST") then
  return Dashboard
end

local function hasType(name, wanted)
  if peripheral.hasType then
    local ok, result = pcall(peripheral.hasType, name, wanted)
    if ok and result then
      return true
    end
  end

  local wrapped = peripheral.wrap(name)
  if not wrapped then
    return false
  end

  if wanted == "inventory" then
    return type(wrapped.list) == "function" and type(wrapped.size) == "function"
  end

  return peripheral.getType(name) == wanted
end

local function writeAt(display, x, y, text, foreground, background, maximumWidth)
  local value = tostring(text or "")
  if maximumWidth then
    value = string.sub(value, 1, math.max(0, maximumWidth))
  end

  display.setCursorPos(x, y)
  display.setTextColor(foreground or colors.white)
  display.setBackgroundColor(background or colors.black)
  display.write(value)
end

local function fill(display, x1, y1, x2, y2, color)
  local width = math.max(0, x2 - x1 + 1)
  display.setBackgroundColor(color)
  for y = y1, y2 do
    display.setCursorPos(x1, y)
    display.write(string.rep(" ", width))
  end
end

local function fitText(text, width)
  local value = tostring(text or "")
  if #value <= width then
    return value
  end
  if width <= 3 then
    return string.sub(value, 1, math.max(0, width))
  end
  return string.sub(value, 1, width - 3) .. "..."
end

local function rightAlign(text, width)
  local value = fitText(text, width)
  return string.rep(" ", math.max(0, width - #value)) .. value
end

local function findMonitor()
  if preferredMonitorName and hasType(preferredMonitorName, "monitor") then
    local preferred = peripheral.wrap(preferredMonitorName)
    preferred.setTextScale(textScale)
    return preferredMonitorName, preferred
  end

  local bestName
  local bestMonitor
  local bestArea = -1

  for _, name in ipairs(peripheral.getNames()) do
    if hasType(name, "monitor") then
      local candidate = peripheral.wrap(name)
      if candidate.getTextScale() ~= textScale then
        candidate.setTextScale(textScale)
      end
      local width, height = candidate.getSize()
      local area = width * height
      if area > bestArea then
        bestName = name
        bestMonitor = candidate
        bestArea = area
      end
    end
  end

  return bestName, bestMonitor
end

local function discoverInventoryNames()
  local names = {}

  if #inventoryNames > 0 then
    for _, name in ipairs(inventoryNames) do
      if peripheral.isPresent(name) and hasType(name, "inventory") then
        table.insert(names, name)
      end
    end
  else
    for _, name in ipairs(peripheral.getNames()) do
      if hasType(name, "inventory") then
        table.insert(names, name)
      end
    end
  end

  table.sort(names)
  return names
end

local capacityCache = {}

local function readCapacity(name, size)
  local cached = capacityCache[name]
  if cached and cached.size == size then
    return cached.capacity
  end

  local capacity = 0
  for slot = 1, size do
    local ok, limit = pcall(peripheral.call, name, "getItemLimit", slot)
    if not ok or type(limit) ~= "number" then
      capacity = size * fallbackItemsPerSlot
      break
    end
    capacity = capacity + limit
  end

  capacityCache[name] = { size = size, capacity = capacity }
  return capacity
end

local function scanInventories()
  local snapshots = {}
  local errors = {}

  for _, name in ipairs(discoverInventoryNames()) do
    local sizeOk, size = pcall(peripheral.call, name, "size")
    local listOk, items = pcall(peripheral.call, name, "list")

    if sizeOk and listOk and type(size) == "number" and type(items) == "table" then
      table.insert(snapshots, {
        name = name,
        size = size,
        capacity = readCapacity(name, size),
        items = items,
      })
    else
      table.insert(errors, name)
    end
  end

  return Dashboard.aggregate(snapshots, fallbackItemsPerSlot), errors
end

local function buildLayout(width, height)
  local rightWidth = math.max(24, math.floor(width * 0.35))
  rightWidth = math.min(rightWidth, math.max(18, width - 30))
  local dividerX = width - rightWidth

  return {
    width = width,
    height = height,
    leftX1 = 1,
    leftX2 = dividerX - 1,
    dividerX = dividerX,
    rightX1 = dividerX + 1,
    rightX2 = width,
    headerY = 1,
    columnHeaderY = 2,
    contentTop = 3,
    contentBottom = math.max(3, height - 2),
    footerY = height,
  }
end

local function percentColor(percent)
  if percent >= 90 then
    return colors.red
  elseif percent >= 75 then
    return colors.orange
  end
  return colors.lime
end

local state = {
  monitorName = nil,
  monitor = nil,
  countMode = defaultCountMode,
  scrollOffset = 0,
  data = Dashboard.aggregate({}, fallbackItemsPerSlot),
  errors = {},
  buttons = {},
}

local function isInside(area, x, y)
  return area and x >= area.x1 and x <= area.x2 and y >= area.y1 and y <= area.y2
end

local function drawButton(name, x1, y, width, label, enabled, active)
  local background = colors.gray
  if enabled then
    background = active and colors.green or colors.blue
  end

  fill(state.monitor, x1, y, x1 + width - 1, y, background)
  local text = fitText(label, width)
  local textX = x1 + math.max(0, math.floor((width - #text) / 2))
  writeAt(state.monitor, textX, y, text, colors.white, background, width)
  state.buttons[name] = { x1 = x1, y1 = y, x2 = x1 + width - 1, y2 = y, enabled = enabled }
end

local function drawHeader(layout)
  fill(state.monitor, 1, layout.headerY, layout.width, layout.headerY, colors.gray)
  writeAt(state.monitor, 2, layout.headerY, "STORAGE NETWORK", colors.yellow, colors.gray, layout.leftX2 - 2)

  local summary = string.format("%d VAULTS  %d ITEMS", #state.data.vaults, #state.data.items)
  local summaryWidth = math.max(0, layout.leftX2 - #"STORAGE NETWORK" - 4)
  if summaryWidth > 0 then
    writeAt(
      state.monitor,
      math.max(2, layout.leftX2 - #summary + 1),
      layout.headerY,
      fitText(summary, summaryWidth),
      colors.lightGray,
      colors.gray,
      summaryWidth
    )
  end

  writeAt(state.monitor, layout.rightX1 + 1, layout.headerY, "VAULT FILL", colors.yellow, colors.gray, layout.rightX2 - layout.rightX1)

  fill(state.monitor, 1, layout.columnHeaderY, layout.width, layout.columnHeaderY, colors.black)
  writeAt(state.monitor, 3, layout.columnHeaderY, "ITEM", colors.lightGray, colors.black, layout.leftX2 - 3)
  local countLabel = state.countMode == "short" and "COUNT (SHORT)" or "COUNT (LONG)"
  writeAt(
    state.monitor,
    math.max(3, layout.leftX2 - #countLabel),
    layout.columnHeaderY,
    countLabel,
    colors.lightGray,
    colors.black,
    #countLabel
  )
  writeAt(state.monitor, layout.rightX1 + 1, layout.columnHeaderY, "VAULT   USED", colors.lightGray, colors.black, layout.rightX2 - layout.rightX1)
end

local function drawItems(layout)
  local visibleRows = math.max(0, layout.contentBottom - layout.contentTop + 1)
  state.scrollOffset = Dashboard.clampOffset(state.scrollOffset, #state.data.items, visibleRows)

  if #state.data.items == 0 then
    writeAt(state.monitor, 3, layout.contentTop + 1, "NO ITEMS FOUND", colors.orange, colors.black, layout.leftX2 - 4)
    writeAt(state.monitor, 3, layout.contentTop + 2, "Check wired modem connections", colors.lightGray, colors.black, layout.leftX2 - 4)
    return visibleRows
  end

  local countWidth = state.countMode == "long" and 16 or 10
  countWidth = math.min(countWidth, math.max(7, math.floor((layout.leftX2 - layout.leftX1) * 0.3)))
  local countX = layout.leftX2 - countWidth
  local nameX = 3
  local nameWidth = math.max(1, countX - nameX - 1)

  for row = 1, visibleRows do
    local index = state.scrollOffset + row
    local item = state.data.items[index]
    if not item then
      break
    end

    local y = layout.contentTop + row - 1
    local rank = string.format("%02d", index)
    writeAt(state.monitor, 1, y, rank, colors.gray, colors.black, 2)
    writeAt(state.monitor, nameX, y, fitText(item.name, nameWidth), colors.white, colors.black, nameWidth)

    local count = "[" .. Dashboard.formatCount(item.count, state.countMode) .. "]"
    writeAt(
      state.monitor,
      countX,
      y,
      rightAlign(count, countWidth),
      colors.cyan,
      colors.black,
      countWidth
    )
  end

  return visibleRows
end

local function drawVaultRow(layout, y, index, vault)
  local availableWidth = layout.rightX2 - layout.rightX1
  local label = string.format("[V%02d]", index)
  local percentage = string.format("[%3d%%]", vault.percent)
  local barWidth = math.max(3, availableWidth - #label - #percentage - 5)
  local bar = "[" .. Dashboard.makeBar(vault.percent, barWidth) .. "]"

  writeAt(state.monitor, layout.rightX1 + 1, y, label, colors.cyan, colors.black, #label)
  writeAt(state.monitor, layout.rightX1 + 1 + #label + 1, y, percentage, percentColor(vault.percent), colors.black, #percentage)
  writeAt(
    state.monitor,
    layout.rightX1 + 1 + #label + #percentage + 2,
    y,
    bar,
    percentColor(vault.percent),
    colors.black,
    math.max(0, layout.rightX2 - (layout.rightX1 + #label + #percentage + 2) + 1)
  )
end

local function drawVaults(layout)
  local visibleRows = math.max(0, layout.contentBottom - layout.contentTop + 1)
  local rowsForVaults = visibleRows
  if #state.data.vaults > visibleRows then
    rowsForVaults = math.max(0, visibleRows - 1)
  end

  for index = 1, math.min(#state.data.vaults, rowsForVaults) do
    drawVaultRow(layout, layout.contentTop + index - 1, index, state.data.vaults[index])
  end

  if #state.data.vaults > rowsForVaults then
    local hidden = #state.data.vaults - rowsForVaults
    writeAt(
      state.monitor,
      layout.rightX1 + 1,
      layout.contentTop + rowsForVaults,
      "+" .. hidden .. " MORE VAULTS",
      colors.lightGray,
      colors.black,
      layout.rightX2 - layout.rightX1
    )
  elseif #state.data.vaults == 0 then
    writeAt(state.monitor, layout.rightX1 + 1, layout.contentTop + 1, "NO VAULTS", colors.orange, colors.black, layout.rightX2 - layout.rightX1)
  end
end

local function drawFooter(layout, visibleItemRows)
  fill(state.monitor, 1, layout.footerY, layout.width, layout.footerY, colors.gray)

  local maxOffset = math.max(0, #state.data.items - visibleItemRows)
  drawButton("up", 2, layout.footerY, 5, "^", state.scrollOffset > 0, false)
  drawButton("down", 8, layout.footerY, 5, "v", state.scrollOffset < maxOffset, false)
  drawButton("mode", 14, layout.footerY, 7, string.upper(state.countMode), true, true)

  local rangeStart = #state.data.items == 0 and 0 or state.scrollOffset + 1
  local rangeEnd = math.min(#state.data.items, state.scrollOffset + visibleItemRows)
  local rangeText = string.format("%d-%d/%d", rangeStart, rangeEnd, #state.data.items)
  writeAt(state.monitor, 22, layout.footerY, rangeText, colors.white, colors.gray, math.max(0, layout.leftX2 - 22))

  local totalLabel = "TOTAL"
  local percentage = string.format("[%3d%%]", state.data.totalPercent)
  local barWidth = math.max(3, (layout.rightX2 - layout.rightX1) - #totalLabel - #percentage - 5)
  local bar = "[" .. Dashboard.makeBar(state.data.totalPercent, barWidth) .. "]"
  local x = layout.rightX1 + 1

  writeAt(state.monitor, x, layout.footerY, totalLabel, colors.white, colors.gray, #totalLabel)
  x = x + #totalLabel + 1
  writeAt(state.monitor, x, layout.footerY, percentage, percentColor(state.data.totalPercent), colors.gray, #percentage)
  x = x + #percentage + 1
  writeAt(state.monitor, x, layout.footerY, bar, percentColor(state.data.totalPercent), colors.gray, math.max(0, layout.rightX2 - x + 1))
end

local function drawDivider(layout)
  fill(state.monitor, layout.dividerX, 1, layout.dividerX, layout.height, colors.lightGray)
end

local function drawDashboard()
  local display = state.monitor
  display.setCursorBlink(false)
  display.setBackgroundColor(colors.black)
  display.setTextColor(colors.white)
  display.clear()

  local width, height = display.getSize()
  if width < 48 or height < 10 then
    writeAt(display, 1, 1, "Monitor too small", colors.red, colors.black, width)
    writeAt(display, 1, 2, "Use the 3x7 monitor at scale 0.5", colors.white, colors.black, width)
    return
  end

  local layout = buildLayout(width, height)
  drawHeader(layout)
  local visibleRows = drawItems(layout)
  drawVaults(layout)
  drawFooter(layout, visibleRows)
  drawDivider(layout)

  if #state.errors > 0 then
    writeAt(display, 2, layout.headerY, "READ ERROR: " .. #state.errors, colors.red, colors.gray, layout.leftX2 - 2)
  end
end

local function resolveMonitor()
  local name, monitor = findMonitor()
  if not monitor then
    error("No monitor found. Attach an Advanced Monitor directly or through a wired modem.")
  end

  state.monitorName = name
  state.monitor = monitor
end

local function refreshData()
  state.data, state.errors = scanInventories()
end

local function handleTouch(monitorName, x, y)
  if monitorName ~= state.monitorName then
    return
  end

  if isInside(state.buttons.up, x, y) and state.buttons.up.enabled then
    state.scrollOffset = state.scrollOffset - 1
  elseif isInside(state.buttons.down, x, y) and state.buttons.down.enabled then
    state.scrollOffset = state.scrollOffset + 1
  elseif isInside(state.buttons.mode, x, y) then
    state.countMode = state.countMode == "short" and "long" or "short"
  else
    return
  end

  drawDashboard()
end

resolveMonitor()
refreshData()
drawDashboard()

local refreshTimer = os.startTimer(refreshSeconds)

while true do
  local event, a, b, c = os.pullEvent()

  if event == "monitor_touch" then
    handleTouch(a, b, c)
  elseif event == "timer" and a == refreshTimer then
    refreshData()
    drawDashboard()
    refreshTimer = os.startTimer(refreshSeconds)
  elseif event == "monitor_resize" and a == state.monitorName then
    drawDashboard()
  elseif event == "peripheral" or event == "peripheral_detach" then
    if event == "peripheral_detach" then
      capacityCache[a] = nil
    end
    resolveMonitor()
    refreshData()
    drawDashboard()
  end
end
