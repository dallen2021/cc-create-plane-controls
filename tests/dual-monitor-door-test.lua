local SCRIPT_PATH = "scripts/dual-monitor-door/startup.lua"

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

local function assertContains(value, expected, label)
  if not string.find(tostring(value), expected, 1, true) then
    fail(string.format("%s: expected %q in %q", label, expected, tostring(value)))
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
  _G.__DUAL_MONITOR_DOOR_TEST = true
  local controller = dofile(SCRIPT_PATH)
  _G.__DUAL_MONITOR_DOOR_TEST = nil
  return controller
end

local ok, controllerOrError = pcall(loadController)
if not ok then
  print("FAIL load dual-monitor door controller")
  print(controllerOrError)
  print("0 passed, 1 failed")
  os.shutdown()
end

local controller = controllerOrError

runTest("outside can open and close while unlocked", function()
  local initial = { door = "closed", locked = false }
  local opened, changed = controller.applyAction(initial, "outside", "open")

  assertEqual(changed, true, "open changed state")
  assertEqual(opened.door, "open", "opened door state")
  assertEqual(opened.locked, false, "opened lock state")
  assertEqual(initial.door, "closed", "input state remains unchanged")

  local closed, closeChanged = controller.applyAction(opened, "outside", "close")
  assertEqual(closeChanged, true, "close changed state")
  assertEqual(closed.door, "closed", "closed door state")
end)

runTest("inside lock disables only the outside open action", function()
  local openState = { door = "open", locked = false }
  local locked, lockChanged = controller.applyAction(openState, "inside", "toggle_lock")

  assertEqual(lockChanged, true, "lock changed state")
  assertEqual(locked.locked, true, "outside access locked")
  assertEqual(controller.isActionEnabled(locked, "outside", "open"), false, "outside open disabled")
  assertEqual(controller.isActionEnabled(locked, "outside", "close"), true, "outside close enabled while open")
  assertEqual(controller.isActionEnabled(locked, "inside", "open"), false, "inside open disabled when already open")

  local closed, closeChanged = controller.applyAction(locked, "outside", "close")
  assertEqual(closeChanged, true, "locked outside close changed state")
  assertEqual(closed.door, "closed", "outside closed locked door")
  assertEqual(closed.locked, true, "close preserves lock")
  assertEqual(controller.isActionEnabled(closed, "outside", "open"), false, "outside remains unable to open")
  assertEqual(controller.isActionEnabled(closed, "outside", "close"), false, "outside close disabled when closed")

  local denied, deniedChanged = controller.applyAction(closed, "outside", "open")
  assertEqual(deniedChanged, false, "locked outside open ignored")
  assertEqual(denied.door, "closed", "denied action preserves door")

  local insideOpened, insideChanged = controller.applyAction(closed, "inside", "open")
  assertEqual(insideChanged, true, "inside can open while locked")
  assertEqual(insideOpened.door, "open", "inside opened locked door")
  assertEqual(insideOpened.locked, true, "inside open preserves lock")
end)

runTest("only the inside panel can change the lock", function()
  local initial = { door = "closed", locked = false }
  local denied, deniedChanged = controller.applyAction(initial, "outside", "toggle_lock")
  assertEqual(deniedChanged, false, "outside lock action ignored")
  assertEqual(denied.locked, false, "outside cannot lock")

  local locked = controller.applyAction(initial, "inside", "toggle_lock")
  local unlocked, unlockChanged = controller.applyAction(locked, "inside", "toggle_lock")
  assertEqual(unlockChanged, true, "unlock changed state")
  assertEqual(unlocked.locked, false, "inside unlocked outside access")
end)

runTest("maps door state to configured redstone levels", function()
  assertEqual(controller.signalForDoor("open", 15, 0), 15, "open signal")
  assertEqual(controller.signalForDoor("closed", 15, 0), 0, "closed signal")
end)

runTest("assigns two monitors predictably and supports explicit roles", function()
  local inside, outside, err = controller.resolveMonitorRoles(
    { "monitor_2", "monitor_1" },
    nil,
    nil
  )
  assertEqual(err, nil, "automatic monitor error")
  assertEqual(inside, "monitor_1", "automatic inside monitor")
  assertEqual(outside, "monitor_2", "automatic outside monitor")

  inside, outside, err = controller.resolveMonitorRoles(
    { "monitor_1", "monitor_2", "monitor_3" },
    "monitor_3",
    "monitor_1"
  )
  assertEqual(err, nil, "explicit monitor error")
  assertEqual(inside, "monitor_3", "explicit inside monitor")
  assertEqual(outside, "monitor_1", "explicit outside monitor")

  inside, outside, err = controller.resolveMonitorRoles(
    { "monitor_1", "monitor_2", "monitor_3" },
    nil,
    nil
  )
  assertEqual(inside, nil, "ambiguous inside monitor")
  assertEqual(outside, nil, "ambiguous outside monitor")
  assertContains(err, "exactly two", "ambiguous monitor error")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.shutdown()
