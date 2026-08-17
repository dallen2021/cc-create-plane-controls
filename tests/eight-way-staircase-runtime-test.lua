local SCRIPT_PATH = "scripts/eight-way-staircase/startup.lua"
local TEST_DONE = "__EIGHT_WAY_STAIRCASE_RUNTIME_DONE__"

local function assertEqual(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 0)
  end
end

local sentSignals = {}
local sleepDurations = {}
local rotateCalls = {}

local bridge = {}

function bridge.getLinkSignal(firstFrequency, secondFrequency)
  if firstFrequency == "minecraft:redstone" and secondFrequency == "minecraft:iron_ingot" then
    return 15
  end

  return 0
end

function bridge.sendLinkSignal(firstFrequency, secondFrequency, strength)
  sentSignals[#sentSignals + 1] = {
    firstFrequency = firstFrequency,
    secondFrequency = secondFrequency,
    strength = strength,
  }
end

local gearshift = {}

function gearshift.rotate(angle, modifier)
  rotateCalls[#rotateCalls + 1] = { angle = angle, modifier = modifier }
end

function gearshift.isRunning()
  return false
end

local fakePeripheral = {}

function fakePeripheral.getNames()
  return { "bridge", "gearshift" }
end

function fakePeripheral.getMethods(name)
  if name == "bridge" then
    return { "getLinkSignal", "sendLinkSignal" }
  end

  if name == "gearshift" then
    return { "rotate", "isRunning" }
  end
end

function fakePeripheral.wrap(name)
  if name == "bridge" then
    return bridge
  end

  if name == "gearshift" then
    return gearshift
  end
end

local files = {
  ["eight_way_staircase_state.txt"] = "sw",
}

local fakeFs = {}

function fakeFs.exists(path)
  return files[path] ~= nil
end

function fakeFs.open(path, mode)
  if mode == "r" then
    return {
      readAll = function()
        return files[path]
      end,
      close = function()
      end,
    }
  end

  if mode == "w" then
    local pieces = {}
    return {
      write = function(value)
        pieces[#pieces + 1] = tostring(value)
      end,
      close = function()
        files[path] = table.concat(pieces)
      end,
    }
  end

  error("Unsupported file mode: " .. tostring(mode), 0)
end

local originalPeripheral = _G.peripheral
local originalFs = _G.fs
local originalTerm = _G.term
local originalPrint = _G.print
local originalSleep = _G.sleep

_G.peripheral = fakePeripheral
_G.fs = fakeFs
_G.term = {
  clear = function()
  end,
  setCursorPos = function()
  end,
}
_G.print = function()
end
_G.sleep = function(seconds)
  sleepDurations[#sleepDurations + 1] = seconds

  if seconds == 0.05 then
    assertEqual(#rotateCalls, 1, "gearshift call count")
    assertEqual(rotateCalls[1].angle, 90, "southwest-to-northwest angle")
    assertEqual(rotateCalls[1].modifier, -1, "southwest-to-northwest modifier")

    assertEqual(#sentSignals, 3, "deployer link signal count")
    for index, expectedStrength in ipairs({ 15, 0, 15 }) do
      local signal = sentSignals[index]
      assertEqual(signal.firstFrequency, "minecraft:diamond", "signal " .. index .. " first frequency")
      assertEqual(signal.secondFrequency, "minecraft:emerald", "signal " .. index .. " second frequency")
      assertEqual(signal.strength, expectedStrength, "signal " .. index .. " strength")
    end

    local releaseCount = 0
    for _, duration in ipairs(sleepDurations) do
      if duration == 0.9 then
        releaseCount = releaseCount + 1
      end
    end

    assertEqual(releaseCount, 1, "18-tick clutch release count")
    assertEqual(files["eight_way_staircase_state.txt"], "nw", "saved heading")
    error(TEST_DONE, 0)
  end
end

_G.__EIGHT_WAY_STAIRCASE_TEST = nil
local ok, err = pcall(dofile, SCRIPT_PATH)

_G.peripheral = originalPeripheral
_G.fs = originalFs
_G.term = originalTerm
_G.print = originalPrint
_G.sleep = originalSleep

if ok or not string.find(tostring(err), TEST_DONE, 1, true) then
  error("Eight-way staircase runtime failed before completing the diagonal docking test: " .. tostring(err), 0)
end

print("PASS docks the bearing with one 18-tick Deployer clutch release at the target diagonal")
os.shutdown()
