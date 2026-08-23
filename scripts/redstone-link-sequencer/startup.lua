local onStrength = 15
local offStrength = 0

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

if rawget(_G, "__REDSTONE_LINK_SEQUENCER_TEST") then
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

local function findBridge()
  for _, name in ipairs(peripheral.getNames()) do
    if hasMethods(name, { "sendLinkSignal" }) then
      return name, peripheral.wrap(name)
    end
  end
end

local bridgeName, bridge = findBridge()
if not bridge then
  error("No Redstone Link Bridge found. Attach it directly or through powered wired modems.")
end

local function sendStep(step)
  local strengths = Controller.strengthsForStep(step)

  for index, link in ipairs(links) do
    bridge.sendLinkSignal(link[1], link[2], strengths[index])
  end
end

local function drawStatus(step)
  term.clear()
  term.setCursorPos(1, 1)
  print("Redstone Link Sequencer")
  print("Bridge: " .. bridgeName)
  print("")

  if step.activeLink then
    print("Link " .. step.activeLink .. " ON")
  else
    print("All links OFF")
  end

  print("Holding for " .. step.seconds .. " second" .. (step.seconds == 1 and "" or "s"))
end

sendStep(steps[#steps])

while true do
  for _, step in ipairs(steps) do
    sendStep(step)
    drawStatus(step)
    sleep(step.seconds)
  end
end
