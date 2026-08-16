local SCRIPT_PATH = "scripts/eight-way-staircase/startup.lua"

local passed = 0
local failed = 0

local function fail(message)
  error(message, 2)
end

local function assertEqual(actual, expected, label)
  if actual ~= expected then
    fail(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local function runTest(name, test)
  local ok, err = pcall(test)
  if ok then
    passed = passed + 1
    print("PASS " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name)
    print(err)
  end
end

local function loadController()
  _G.__EIGHT_WAY_STAIRCASE_TEST = true
  local controller = dofile(SCRIPT_PATH)
  _G.__EIGHT_WAY_STAIRCASE_TEST = nil
  return controller
end

local ok, controllerOrError = pcall(loadController)
if not ok then
  print("FAIL load eight-way staircase controller")
  print(controllerOrError)
  print("0 passed, 1 failed")
  os.shutdown()
end

local controller = controllerOrError

runTest("starts at southeast when no saved heading exists", function()
  assertEqual(controller.defaultHeading, "se", "default heading")
end)

runTest("uses the configured eight physical Redstone Link channels", function()
  local expected = {
    north = { "minecraft:compass", "minecraft:redstone" },
    ne = { "minecraft:redstone", "minecraft:gold_ingot" },
    east = { "minecraft:compass", "minecraft:gold_ingot" },
    se = { "minecraft:lapis_lazuli", "minecraft:gold_ingot" },
    south = { "minecraft:compass", "minecraft:lapis_lazuli" },
    sw = { "minecraft:lapis_lazuli", "minecraft:iron_ingot" },
    west = { "minecraft:compass", "minecraft:iron_ingot" },
    nw = { "minecraft:redstone", "minecraft:iron_ingot" },
  }

  for heading, channel in pairs(expected) do
    assertEqual(controller.buttonChannels[heading][1], channel[1], heading .. " first frequency")
    assertEqual(controller.buttonChannels[heading][2], channel[2], heading .. " second frequency")
  end
end)

runTest("turns southeast to east by 45 degrees", function()
  local plan = controller.resolveTurn("se", "east")

  assertEqual(plan.angle, 45, "southeast-to-east angle")
  assertEqual(plan.modifier, 1, "southeast-to-east modifier")
end)

runTest("turns southeast to south by 45 degrees", function()
  local plan = controller.resolveTurn("se", "south")

  assertEqual(plan.angle, 45, "southeast-to-south angle")
  assertEqual(plan.modifier, -1, "southeast-to-south modifier")
end)

runTest("takes the short 135 degree route between cardinal and diagonal headings", function()
  local plan = controller.resolveTurn("north", "sw")

  assertEqual(plan.angle, 135, "north-to-southwest angle")
  assertEqual(plan.modifier, 1, "north-to-southwest modifier")
end)

runTest("turns opposite headings by 180 degrees", function()
  local plan = controller.resolveTurn("se", "nw")

  assertEqual(plan.angle, 180, "southeast-to-northwest angle")
  assertEqual(plan.modifier, 1, "southeast-to-northwest modifier")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.shutdown()
