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

Current throttle input sides:

```lua
local throttleSides = { "back", "bottom" }
```

If both sides are powered, the script uses the stronger analog signal.

### Landing Gear Cockpit Controller

Path:

```text
scripts/landing-gear-cockpit/startup.lua
```

Use this on cockpit computer `10`. It draws cockpit monitor controls for landing gear and cargo door.

Landing gear buttons:

```text
GEAR UP
GEAR DOWN
```

Cargo door buttons:

```text
RAISE
LOWER
```

When a button is pressed, it sends a wireless rednet command to the matching receiver computer.

Current wireless modem side:

```lua
local modemSide = "right"
```

Current landing gear receiver:

```lua
local landingReceiverId = 11
```

Current cargo door receiver:

```lua
local cargoReceiverId = 15
```

Current landing gear monitor position:

```lua
local landingMonitorSection = 2
local landingMonitorSections = 5
```

This puts the landing gear UI in the second section from the left on a 1x5 monitor. The script only clears and redraws that section.

Current cargo monitor preference:

```lua
local cargoMonitorName = "left"
```

If a separate left-side monitor is attached, the cargo UI uses that whole monitor. If no separate side monitor is found, it falls back to section `3` of the wide 1x5 monitor.

### Cargo Lift Top Controller

Path:

```text
scripts/cargo-lift-top/startup.lua
```

Use this on top-panel computer `14`. It draws cargo lift controls in the left section of the 1x3 top monitor and sends wireless commands to the cargo receiver.

Buttons:

```text
RAISE
LOWER
```

Current wireless modem side:

```lua
local modemSide = "front"
```

Current cargo receiver:

```lua
local receiverId = 15
```

Current top monitor position:

```lua
local monitorName = "top"
local monitorSection = 1
local monitorSections = 3
```

### Landing Gear Receiver

Path:

```text
scripts/landing-gear-receiver/startup.lua
```

Use this on landing gear computer `11`. It receives wireless commands from the cockpit computer and rotates the local Sequenced Gearshift by 180 degrees.

Current wireless modem side:

```lua
local modemSide = "right"
```

Current allowed cockpit computer:

```lua
local cockpitId = 10
```

Current gear movement settings:

```lua
local rotateDegrees = 180
local downModifier = 1
local upModifier = -1
local defaultState = "up"
```

If the landing gear moves backward, swap `downModifier` and `upModifier`. The script saves its last gear state in `landing_gear_state.txt`, so pressing the same button twice will not rotate the gear twice.

### Cargo Door Receiver

Path:

```text
scripts/cargo-door-receiver/startup.lua
```

Use this on the cargo door receiver computer. It receives wireless commands from cockpit computer `10` and top-panel computer `14`, then rotates the local Sequenced Gearshift to raise/lower the rear cargo entrance.

Current wireless modem side:

```lua
local modemSide = "front"
```

Current allowed cockpit computers:

```lua
local cockpitIds = { 10, 14 }
```

Current cargo movement settings:

```lua
local rotateDegrees = 90
local lowerModifier = 1
local raiseModifier = -1
local defaultState = "up"
```

If the cargo door moves backward, swap `lowerModifier` and `raiseModifier`. If it needs to travel farther, change `rotateDegrees`. The script saves its last door state in `cargo_door_state.txt`.

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

Cockpit controller, for computer `10`:

```lua
wget https://raw.githubusercontent.com/dallen2021/cc-create-plane-controls/main/scripts/landing-gear-cockpit/startup.lua startup.lua
reboot
```

Cargo lift top controller, for computer `14`:

```lua
wget https://raw.githubusercontent.com/dallen2021/cc-create-plane-controls/main/scripts/cargo-lift-top/startup.lua startup.lua
reboot
```

Landing gear receiver, for computer `11`:

```lua
wget https://raw.githubusercontent.com/dallen2021/cc-create-plane-controls/main/scripts/landing-gear-receiver/startup.lua startup.lua
reboot
```

Cargo door receiver, for the cargo receiver computer:

```lua
wget https://raw.githubusercontent.com/dallen2021/cc-create-plane-controls/main/scripts/cargo-door-receiver/startup.lua startup.lua
reboot
```

## Create Wiring Notes

For direct peripheral control, the CC:Tweaked computer must see the Sequenced Gearshift as a peripheral. Use either:

- a gearshift directly adjacent to the computer, or
- wired modems plus networking cable.

Wireless modems are useful for computer-to-computer messages, but they do not make a distant Sequenced Gearshift appear as a directly callable peripheral.

For landing gear, that means:

```text
computer 10 + monitors + wireless modem on right
        sends wireless commands
computer 11 + wireless modem on right + local gearshift peripheral
        rotates landing gear bearing
computer 15 + wireless modem on front + local gearshift peripheral
        rotates rear cargo entrance bearing
computer 14 + 1x3 top monitor + wireless modem on front
        sends cargo lift commands from the left top-monitor section
```

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
