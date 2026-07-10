local SCRIPT_PATH = "repo/scripts/vault-storage/startup.lua"

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

local function loadDashboard()
  _G.__VAULT_STORAGE_TEST = true
  local dashboard = dofile(SCRIPT_PATH)
  _G.__VAULT_STORAGE_TEST = nil
  return dashboard
end

local ok, dashboardOrError = pcall(loadDashboard)
if not ok then
  print("FAIL load dashboard")
  print(dashboardOrError)
  print("0 passed, 1 failed")
  os.shutdown()
end

local dashboard = dashboardOrError

runTest("formats short and long item counts", function()
  assertEqual(dashboard.formatCount(999, "short"), "999", "small short count")
  assertEqual(dashboard.formatCount(1500, "short"), "1.5k", "thousands short count")
  assertEqual(dashboard.formatCount(12840, "short"), "12.8k", "large thousands short count")
  assertEqual(dashboard.formatCount(999999, "short"), "1M", "rounded unit rollover")
  assertEqual(dashboard.formatCount(1500, "long"), "1,500", "thousands long count")
  assertEqual(dashboard.formatCount(1234567, "long"), "1,234,567", "millions long count")
end)

runTest("aggregates items and sorts greatest to least", function()
  local result = dashboard.aggregate({
    {
      name = "create:item_vault_0",
      size = 10,
      items = {
        [1] = { name = "minecraft:iron_ingot", count = 64 },
        [2] = { name = "minecraft:cobblestone", count = 128 },
      },
    },
    {
      name = "create:item_vault_1",
      size = 5,
      items = {
        [1] = { name = "minecraft:iron_ingot", count = 32 },
        [2] = { name = "minecraft:oak_log", count = 64 },
      },
    },
  }, 64)

  assertEqual(#result.items, 3, "unique item count")
  assertEqual(result.items[1].name, "Cobblestone", "first item")
  assertEqual(result.items[1].count, 128, "first item count")
  assertEqual(result.items[2].name, "Iron Ingot", "second item")
  assertEqual(result.items[2].count, 96, "second item count")
  assertEqual(result.items[3].name, "Oak Log", "third item")
  assertEqual(result.totalItems, 288, "total stored items")
end)

runTest("calculates per-vault and total fill percentages", function()
  local result = dashboard.aggregate({
    {
      name = "vault_a",
      size = 10,
      items = {
        [1] = { name = "minecraft:stone", count = 192 },
      },
    },
    {
      name = "vault_b",
      size = 5,
      items = {
        [1] = { name = "minecraft:dirt", count = 96 },
      },
    },
  }, 64)

  assertEqual(result.vaults[1].percent, 30, "first vault fill")
  assertEqual(result.vaults[2].percent, 30, "second vault fill")
  assertEqual(result.totalPercent, 30, "total fill")
end)

runTest("clamps item scrolling to the visible range", function()
  assertEqual(dashboard.clampOffset(-3, 20, 5), 0, "negative offset")
  assertEqual(dashboard.clampOffset(7, 20, 5), 7, "middle offset")
  assertEqual(dashboard.clampOffset(99, 20, 5), 15, "past last page")
  assertEqual(dashboard.clampOffset(5, 3, 8), 0, "short list")
end)

runTest("builds fixed-width percentage bars", function()
  assertEqual(dashboard.makeBar(0, 10), "----------", "empty bar")
  assertEqual(dashboard.makeBar(55, 10), "######----", "partial bar")
  assertEqual(dashboard.makeBar(100, 10), "##########", "full bar")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.shutdown()
