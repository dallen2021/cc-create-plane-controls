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

runTest("starts at southwest when no saved heading exists", function()
  assertEqual(controller.defaultHeading, "sw", "default heading")
end)

runTest("uses the configured Redstone Link channels", function()
  local expected = {
    north = { "minecraft:compass", "minecraft:redstone" },
    ne = { "minecraft:redstone", "minecraft:gold_ingot" },
    east = { "minecraft:compass", "minecraft:gold_ingot" },
    se = { "minecraft:lapis_lazuli", "minecraft:gold_ingot" },
    south = { "minecraft:compass", "minecraft:lapis_lazuli" },
    sw = { "minecraft:lapis_lazuli", "minecraft:iron_ingot" },
    west = { "minecraft:compass", "minecraft:iron_ingot" },
    nw = { "minecraft:redstone", "minecraft:iron_ingot" },
    entrance = { "minecraft:emerald", "minecraft:emerald" },
  }

  for heading, channel in pairs(expected) do
    assertEqual(controller.buttonChannels[heading][1], channel[1], heading .. " first frequency")
    assertEqual(controller.buttonChannels[heading][2], channel[2], heading .. " second frequency")
  end
end)

runTest("polls the entrance control", function()
  local foundEntrance = false

  for _, button in ipairs(controller.buttonOrder) do
    if button == "entrance" then
      foundEntrance = true
    end
  end

  assertEqual(foundEntrance, true, "entrance poll order")
end)

runTest("accepts one unambiguous button press", function()
  local command = controller.selectActiveButton({ "south" }, { "south" }, "sw")

  assertEqual(command.target, "south", "single-button target")
  assertEqual(command.message, "Last input: SOUTH", "single-button message")
end)

runTest("rejects simultaneous button signals", function()
  local command = controller.selectActiveButton({ "east", "south" }, { "east", "south" }, "sw")

  assertEqual(command.target, nil, "conflicting target")
  assertEqual(command.message, "Conflicting signals: EAST + SOUTH", "conflicting message")
end)

runTest("routes the entrance control to southwest from another heading", function()
  assertEqual(controller.resolveButtonTarget("entrance", "north"), "sw", "north entrance target")
  assertEqual(controller.resolveButtonTarget("entrance", "east"), "sw", "east entrance target")
end)

runTest("routes the entrance control from southwest to south", function()
  assertEqual(controller.resolveButtonTarget("entrance", "sw"), "south", "southwest entrance target")
end)

runTest("uses the recorded heading when an entrance signal is pressed", function()
  local approach = controller.selectActiveButton({ "entrance" }, { "entrance" }, "west")
  local exit = controller.selectActiveButton({ "entrance" }, { "entrance" }, "sw")

  assertEqual(approach.target, "sw", "entrance approach target")
  assertEqual(exit.target, "south", "entrance exit target")
end)

runTest("turns southwest to west by 45 degrees", function()
  local plan = controller.resolveTurn("sw", "west")

  assertEqual(plan.angle, 45, "southwest-to-west angle")
  assertEqual(plan.modifier, -1, "southwest-to-west modifier")
end)

runTest("turns southwest to south by 45 degrees", function()
  local plan = controller.resolveTurn("sw", "south")

  assertEqual(plan.angle, 45, "southwest-to-south angle")
  assertEqual(plan.modifier, 1, "southwest-to-south modifier")
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
