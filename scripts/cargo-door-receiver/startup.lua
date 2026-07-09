local modemSide = "right"
local protocol = "plane_cargo_door"
local cockpitId = 10
local preferredGearshiftName = nil

local rotateDegrees = 90
local lowerModifier = 1
local raiseModifier = -1
local defaultState = "up"
local stateFile = "cargo_door_state.txt"

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

local function loadState()
  if not fs.exists(stateFile) then
    return defaultState
  end

  local handle = fs.open(stateFile, "r")
  local value = string.lower((handle.readAll() or ""):gsub("%s+", ""))
  handle.close()

  if value == "up" or value == "down" then
    return value
  end

  return defaultState
end

local function saveState(state)
  local handle = fs.open(stateFile, "w")
  handle.write(state)
  handle.close()
end

local function reply(receiverId, message)
  rednet.send(receiverId, message, protocol)
end

local function drawStatus(gearshiftName, state, message)
  term.clear()
  term.setCursorPos(1, 1)
  print("Cargo door receiver")
  print("Computer ID: " .. os.getComputerID())
  print("Wireless: " .. modemSide)
  print("Cockpit ID: " .. cockpitId)
  print("Gearshift: " .. gearshiftName)
  print("State: " .. state)
  print("Protocol: " .. protocol)
  print("")
  print(message or "Waiting for cockpit")
end

requireWirelessModem(modemSide)

local gearshiftName, gearshift = findGearshift()
if not gearshift then
  error("No Sequenced Gearshift found. Attach it with a wired modem/network cable or place it next to this computer.")
end

local currentState = loadState()
saveState(currentState)
drawStatus(gearshiftName, currentState)

while true do
  local sender, message = rednet.receive(protocol)

  if sender ~= cockpitId then
    drawStatus(gearshiftName, currentState, "Ignored command from #" .. sender)
  elseif message == "status" then
    reply(sender, "cargo_" .. currentState)
  elseif message == "up" or message == "down" then
    if message == currentState then
      reply(sender, "already_" .. message)
      drawStatus(gearshiftName, currentState, "Already " .. string.upper(message))
    elseif gearshift.isRunning() then
      reply(sender, "busy")
      drawStatus(gearshiftName, currentState, "Gearshift is busy")
    else
      local modifier = message == "down" and lowerModifier or raiseModifier
      reply(sender, "moving_" .. message)
      drawStatus(gearshiftName, currentState, "Moving " .. string.upper(message))

      local ok, err = pcall(function()
        gearshift.rotate(rotateDegrees, modifier)
      end)

      if not ok then
        reply(sender, "error:" .. tostring(err))
        drawStatus(gearshiftName, currentState, "Error: " .. tostring(err))
      else
        while gearshift.isRunning() do
          sleep(0.05)
        end

        currentState = message
        saveState(currentState)
        reply(sender, "cargo_" .. currentState)
        drawStatus(gearshiftName, currentState, "Cargo door is " .. string.upper(currentState))
      end
    end
  else
    reply(sender, "error:unknown command")
  end
end
