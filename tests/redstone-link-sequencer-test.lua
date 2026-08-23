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

if failed > 0 then
  error(string.format("%d passed, %d failed", passed, failed), 0)
end

print(string.format("%d passed, %d failed", passed, failed))
if os.shutdown then
  os.shutdown()
end
