# CC:Tweaked + Create Plane Controls

Lua scripts for controlling Create contraptions with CC:Tweaked computers in the `LBSMP 2` modpack.

## Scripts

### Bearing Monitor Controller

Path:

```text
scripts/bearing-monitor/startup.lua
```

Use this on the monitor/button computer. It draws monitor buttons for `-90`, `+90`, `-180`, and `+180`, then calls a Sequenced Gearshift to rotate a Mechanical Bearing.

Current default gearshift:

```lua
local preferredGearshiftName = "Create_SequencedGearshift_0"
```

### Flap Throttle Controller

Path:

```text
scripts/flap-throttle/startup.lua
```

Use this on the flap computer. It reads an analog redstone throttle lever and rotates a Sequenced Gearshift to the matching flap angle.

Current mapping:

```text
redstone 0  = -21 degrees
redstone 1  = -18
redstone 2  = -15
redstone 3  = -12
redstone 4  = -9
redstone 5  = -6
redstone 6  = -3
redstone 7  = 0
redstone 8  = 0
redstone 9  = +3
redstone 10 = +6
redstone 11 = +9
redstone 12 = +12
redstone 13 = +15
redstone 14 = +18
redstone 15 = +21
```

It also displays the power level and target degrees on a connected monitor.

Current throttle side:

```lua
local throttleSide = "back"
```

## Install In Singleplayer

Copy the script you want into the target computer folder as `startup.lua`.

Example local world path:

```text
C:\Users\daniel\AppData\Roaming\ModrinthApp\profiles\LBSMP 2\saves\TestWorld\computercraft\computer\<computer id>\startup.lua
```

Then reboot the in-game computer:

```lua
reboot
```

## Install From GitHub In Game

If CC:Tweaked HTTP is enabled, run one of these on the target in-game computer.

Bearing monitor controller:

```lua
wget https://raw.githubusercontent.com/dallen2021/cc-create-plane-controls/main/scripts/bearing-monitor/startup.lua startup.lua
reboot
```

Flap throttle controller:

```lua
wget https://raw.githubusercontent.com/dallen2021/cc-create-plane-controls/main/scripts/flap-throttle/startup.lua startup.lua
reboot
```

## Create Wiring Notes

For direct peripheral control, the CC:Tweaked computer must see the Sequenced Gearshift as a peripheral. Use either:

- a gearshift directly adjacent to the computer, or
- wired modems plus networking cable.

Wireless modems are useful for computer-to-computer messages, but they do not make a distant Sequenced Gearshift appear as a directly callable peripheral.

## Useful Commands

List visible peripherals:

```lua
for _, name in ipairs(peripheral.getNames()) do
  print(name, peripheral.getType(name))
end
```

Test a gearshift directly:

```lua
peripheral.call("Create_SequencedGearshift_0", "rotate", 90, 1)
```

Reverse:

```lua
peripheral.call("Create_SequencedGearshift_0", "rotate", 90, -1)
```
