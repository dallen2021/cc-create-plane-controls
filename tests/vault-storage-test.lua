local SCRIPT_PATH = "scripts/vault-storage/startup.lua"

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

runTest("calculates and formats signed per-second item rates", function()
  local baseline = {
    items = {
      { id = "minecraft:iron_ingot", count = 100 },
    },
  }
  local baselineCounts = dashboard.applyItemRates(baseline, nil, nil)

  assertEqual(baseline.items[1].rate, 0, "baseline rate")

  local changed = {
    items = {
      { id = "minecraft:iron_ingot", count = 130 },
      { id = "minecraft:gold_ingot", count = 5 },
    },
  }
  local changedCounts = dashboard.applyItemRates(changed, baselineCounts, 5)

  assertEqual(changed.items[1].rate, 6, "increasing item rate")
  assertEqual(changed.items[2].rate, 1, "new item rate")
  assertEqual(dashboard.formatRate(changed.items[1].rate, "short"), "+6/s", "positive rate")

  local decreased = {
    items = {
      { id = "minecraft:iron_ingot", count = 125 },
      { id = "minecraft:gold_ingot", count = 5 },
    },
  }
  dashboard.applyItemRates(decreased, changedCounts, 2)

  assertEqual(decreased.items[1].rate, -2.5, "decreasing item rate")
  assertEqual(dashboard.formatRate(decreased.items[1].rate, "long"), "-2.5/s", "negative rate")
  assertEqual(dashboard.formatRate(decreased.items[2].rate, "short"), "0/s", "unchanged rate")
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

runTest("calculates fixed-width block bar fills", function()
  assertEqual(dashboard.barFill(0, 10), 0, "empty bar")
  assertEqual(dashboard.barFill(55, 10), 6, "partial bar")
  assertEqual(dashboard.barFill(100, 10), 10, "full bar")
end)

runTest("recognizes vault peripherals without counting every inventory", function()
  assertEqual(
    dashboard.isVaultPeripheral("create:item_vault_0", { "inventory" }),
    true,
    "vault peripheral name"
  )
  assertEqual(
    dashboard.isVaultPeripheral("wired_inventory_0", { "create:item_vault", "inventory" }),
    true,
    "vault peripheral type"
  )
  assertEqual(
    dashboard.isVaultPeripheral("minecraft:chest_0", { "minecraft:chest", "inventory" }),
    false,
    "non-vault inventory"
  )
end)

runTest("creates stable signatures for unchanged dashboard data", function()
  local first = {
    items = { { id = "minecraft:stone", count = 64 } },
    vaults = { { sourceName = "create:item_vault_0", itemCount = 64, capacity = 640 } },
    totalItems = 64,
    totalCapacity = 640,
    totalPercent = 10,
  }
  local same = {
    items = { { id = "minecraft:stone", count = 64 } },
    vaults = { { sourceName = "create:item_vault_0", itemCount = 64, capacity = 640 } },
    totalItems = 64,
    totalCapacity = 640,
    totalPercent = 10,
  }
  local changed = {
    items = { { id = "minecraft:stone", count = 65 } },
    vaults = { { sourceName = "create:item_vault_0", itemCount = 65, capacity = 640 } },
    totalItems = 65,
    totalCapacity = 640,
    totalPercent = 10,
  }

  local firstSignature = dashboard.dataSignature(first, {})
  assertEqual(firstSignature, dashboard.dataSignature(same, {}), "unchanged signature")
  if firstSignature == dashboard.dataSignature(changed, {}) then
    fail("changed inventory data must produce a different signature")
  end
end)

print(string.format("%d passed, %d failed", passed, failed))
os.shutdown()
