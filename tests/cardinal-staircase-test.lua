local SCRIPT_PATH = "scripts/cardinal-staircase/startup.lua"

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
  _G.__CARDINAL_STAIRCASE_TEST = true
  local controller = dofile(SCRIPT_PATH)
  _G.__CARDINAL_STAIRCASE_TEST = nil
  return controller
end

local ok, controllerOrError = pcall(loadController)
if not ok then
  print("FAIL load cardinal staircase controller")
  print(controllerOrError)
  print("0 passed, 1 failed")
  os.shutdown()
end

local controller = controllerOrError

runTest("keeps the staircase still when it already faces the requested direction", function()
  local plan = controller.resolveTurn("south", "south")

  assertEqual(plan.angle, 0, "same-direction angle")
  assertEqual(plan.modifier, 0, "same-direction modifier")
end)

runTest("turns south to east by 90 degrees counterclockwise", function()
  local plan = controller.resolveTurn("south", "east")

  assertEqual(plan.angle, 90, "south-to-east angle")
  assertEqual(plan.modifier, -1, "south-to-east modifier")
end)

runTest("turns south to west by 90 degrees clockwise", function()
  local plan = controller.resolveTurn("south", "west")

  assertEqual(plan.angle, 90, "south-to-west angle")
  assertEqual(plan.modifier, 1, "south-to-west modifier")
end)

runTest("turns south to north by 180 degrees", function()
  local plan = controller.resolveTurn("south", "north")

  assertEqual(plan.angle, 180, "south-to-north angle")
  assertEqual(plan.modifier, 1, "south-to-north modifier")
end)

runTest("uses the shortest 90 degree turn for every adjacent cardinal pair", function()
  local clockwise = controller.resolveTurn("north", "east")
  local counterclockwise = controller.resolveTurn("north", "west")

  assertEqual(clockwise.angle, 90, "north-to-east angle")
  assertEqual(clockwise.modifier, 1, "north-to-east modifier")
  assertEqual(counterclockwise.angle, 90, "north-to-west angle")
  assertEqual(counterclockwise.modifier, -1, "north-to-west modifier")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.shutdown()
