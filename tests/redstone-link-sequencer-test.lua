local SCRIPT_PATH = "scripts/redstone-link-sequencer/startup.lua"

local passed = 0
local failed = 0

local function assertEqual(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 0)
  end
end

local function assertTableEqual(actual, expected, label)
  assertEqual(#actual, #expected, label .. " length")

  for index, expectedValue in ipairs(expected) do
    assertEqual(actual[index], expectedValue, label .. " entry " .. index)
  end
end

local function runTest(name, test)
  local ok, err = pcall(test)
  if ok then
    passed = passed + 1
    print("PASS " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end

_G.__REDSTONE_LINK_SEQUENCER_TEST = true
local loaded, Controller = pcall(dofile, SCRIPT_PATH)
_G.__REDSTONE_LINK_SEQUENCER_TEST = nil

runTest("uses the four requested channels and one-link-at-a-time timing cycle", function()
  assertEqual(loaded, true, "sequence controller loads")

  assertEqual(Controller.onStrength, 15, "on strength")
  assertEqual(Controller.offStrength, 0, "off strength")
  assertEqual(#Controller.links, 4, "link count")

  local expectedLinks = {
    { "minecraft:red_sandstone", "minecraft:sandstone" },
    { "minecraft:red_sandstone", "minecraft:red_sandstone" },
    { "minecraft:sandstone", "minecraft:red_sandstone" },
    { "minecraft:sandstone", "minecraft:sandstone" },
  }

  for index, expectedLink in ipairs(expectedLinks) do
    assertTableEqual(Controller.links[index], expectedLink, "link " .. index)
  end

  local expectedSteps = {
    { activeLink = 1, seconds = 1, strengths = { 15, 0, 0, 0 } },
    { activeLink = 2, seconds = 1, strengths = { 0, 15, 0, 0 } },
    { activeLink = 3, seconds = 1, strengths = { 0, 0, 15, 0 } },
    { activeLink = 4, seconds = 5, strengths = { 0, 0, 0, 15 } },
    { activeLink = nil, seconds = 10, strengths = { 0, 0, 0, 0 } },
  }

  assertEqual(#Controller.steps, #expectedSteps, "step count")
  for index, expectedStep in ipairs(expectedSteps) do
    local step = Controller.steps[index]
    assertEqual(step.activeLink, expectedStep.activeLink, "step " .. index .. " active link")
    assertEqual(step.seconds, expectedStep.seconds, "step " .. index .. " duration")
    assertTableEqual(Controller.strengthsForStep(step), expectedStep.strengths, "step " .. index .. " strengths")
  end
end)

runTest("main service disconnect gates both banks of side breakers", function()
  local initial = Controller.newState()
  assertEqual(initial.mainOn, false, "main starts off")
  assertEqual(Controller.isBreakerOn(initial, "left", 1), false, "left breaker is dark while service is off")
  assertEqual(Controller.isBreakerOn(initial, "right", 8), false, "right breaker is dark while service is off")

  local serviceOn, serviceChanged = Controller.toggleMain(initial)
  assertEqual(serviceChanged, true, "main turns on")
  assertEqual(serviceOn.mainOn, true, "main on state")
  assertEqual(Controller.isBreakerOn(serviceOn, "left", 1), true, "left breaker receives service")
  assertEqual(Controller.isBreakerOn(serviceOn, "right", 8), true, "right breaker receives service")

  local leftOff, leftChanged = Controller.toggleBreaker(serviceOn, "left", 1)
  assertEqual(leftChanged, true, "left breaker toggles while service is on")
  assertEqual(Controller.isBreakerOn(leftOff, "left", 1), false, "left breaker turns off")
  assertEqual(Controller.isBreakerOn(leftOff, "right", 8), true, "other breaker remains on")

  local serviceOff = Controller.toggleMain(leftOff)
  assertEqual(Controller.isBreakerOn(serviceOff, "left", 1), false, "left breaker remains dark after disconnect")
  assertEqual(Controller.isBreakerOn(serviceOff, "right", 8), false, "main disconnect cuts every right breaker")

  local restored = Controller.toggleMain(serviceOff)
  assertEqual(Controller.isBreakerOn(restored, "left", 1), false, "individual left breaker position is preserved")
  assertEqual(Controller.isBreakerOn(restored, "right", 8), true, "other right breaker returns with service")
end)

runTest("requires the master and all four red arming switches before running", function()
  local initial = Controller.newState()
  local denied, deniedChanged = Controller.toggleArmingSwitch(initial, 1)
  assertEqual(deniedChanged, false, "arming switch ignores touches while service is off")
  assertEqual(Controller.isSequenceArmed(denied), false, "service-off panel cannot arm")

  local state = Controller.toggleMain(initial)
  for index = 1, 3 do
    state = Controller.toggleArmingSwitch(state, index)
    assertEqual(Controller.isSequenceArmed(state), false, "sequence waits for arming switch " .. (index + 1))
  end

  state = Controller.toggleArmingSwitch(state, 4)
  assertEqual(Controller.isSequenceArmed(state), true, "all four red switches arm the sequence")

  state = Controller.toggleArmingSwitch(state, 2)
  assertEqual(Controller.isSequenceArmed(state), false, "turning off one red switch stops the sequence")

  state = Controller.toggleArmingSwitch(state, 2)
  state = Controller.toggleMain(state)
  assertEqual(Controller.isSequenceArmed(state), false, "main disconnect stops an otherwise armed sequence")
end)

if failed > 0 then
  error(string.format("%d passed, %d failed", passed, failed), 0)
end

print(string.format("%d passed, %d failed", passed, failed))
if os.shutdown then
  os.shutdown()
end
