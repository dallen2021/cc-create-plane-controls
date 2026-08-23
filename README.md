# CC:Tweaked + Create Controls

Lua scripts for controlling Create contraptions and monitoring storage with CC:Tweaked computers in the `LBSMP 2` modpack.

## Scripts

### Cardinal Staircase Controller

Path:

```text
scripts/cardinal-staircase/startup.lua
```

Use this on a CC:Tweaked computer connected by wired modems to both a Redstone Link Bridge and a Create Sequenced Gearshift. It receives four ordinary Create Redstone Link transmitter channels and turns a Mechanical Bearing to the requested cardinal direction using the shortest 90-degree or 180-degree move.

Set the staircase's physical starting direction once with:

```lua
local defaultHeading = "north"
```

The controller saves each completed heading in `cardinal_staircase_state.txt`, so normal computer reboots preserve its direction. If the bearing is manually moved or interrupted partway through a turn, delete that state file and set `defaultHeading` to its real direction before rebooting.

Configure the button transmitters with these frequency pairs, in this order:

```text
North: Compass + Redstone
East:  Compass + Gold Ingot
South: Compass + Lapis Lazuli
West:  Compass + Iron Ingot
```

Keep those physical transmitter frequencies as listed. The controller deliberately compensates for this bearing's mirrored East/West direction internally.

For this bearing, viewed from above, `modifier = 1` turns counterclockwise and `modifier = -1` turns clockwise. The controllers already account for that direction.

### Eight-Way Staircase Controller (45 Degrees)

Path:

```text
scripts/eight-way-staircase/startup.lua
```

This is a separate controller for the same bridge/gearshift arrangement. It retains the cardinal button links and adds diagonal targets, tracks the physical eight-way heading, and starts at **SW** when `eight_way_staircase_state.txt` does not exist.

```text
North: Compass + Redstone
NE:    Redstone + Gold Ingot
East:  Compass + Gold Ingot
SE:    Lapis Lazuli + Gold Ingot
South: Compass + Lapis Lazuli
SW:    Lapis Lazuli + Iron Ingot
West:  Compass + Iron Ingot
NW:    Redstone + Iron Ingot
Entrance: Emerald + Emerald
```

Set the staircase physically to SW before the first run. From SW, the West and South buttons each make a 45-degree turn.

The **Entrance** control is state-aware: it sends the staircase to SW from any other recorded heading. Press it again while the computer reports SW and it rotates to South so the player can exit.

The controller accepts one active button signal at a time. If multiple link channels are powered, it will not rotate and will show the conflicting labels on the computer screen.

#### Diagonal docking with a Deployer

Set the Mechanical Bearing to **Only place when anchor is destroyed**. Place an empty, stationary Create Deployer in **Use** mode facing the bearing, and power the Deployer through a clutch. The clutch prevents the Deployer from moving while it receives redstone power.

Attach an ordinary Create Redstone Link receiver to that clutch and configure it with:

```text
Diamond + Emerald
```

The controller holds that channel at redstone strength `15` while idle. It removes the signal once, for `18` ticks (`0.9` seconds), only after a move reaches a diagonal target so the staircase docks there. It does not pulse before a turn, and cardinal targets receive no click, so they remain contraptions.

Keep the Deployer's hand empty. The controller restores the link to strength `15` after every release and on normal startup.

### Redstone Link Sequencer

Path:

```text
scripts/redstone-link-sequencer/startup.lua
```

Use this on a CC:Tweaked computer connected to a Redstone Link Bridge. Configure four ordinary Create Redstone Link receivers with these frequencies:

```text
Link 1: Red Sandstone + Sandstone
Link 2: Red Sandstone + Red Sandstone
Link 3: Sandstone + Red Sandstone
Link 4: Sandstone + Sandstone
```

It repeats this cycle indefinitely, with every other link set to `0` while the listed link is set to `15`:

```text
Link 1 on for 1 second
Link 2 on for 1 second
Link 3 on for 1 second
Link 4 on for 5 seconds
All links off for 10 seconds
```

On startup, it first sends all four links an off signal so an old powered state cannot remain active.

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

### Dual-Monitor Door Controller

Path:

```text
scripts/dual-monitor-door/startup.lua
```

Use this on one computer connected to two `1`-wide by `2`-high Advanced Monitors and an ordinary Create Redstone Link. At text scale `0.5`, each portrait monitor reports a `15x24` character area and automatically uses compact labels. The computer holds a continuous redstone level on the link: `15` while the door should be open and `0` while it should be closed.

Both monitors have `OPEN` and `CLOSE` buttons. The inside monitor also has `LOCK OUTSIDE`; its compact unlock label is `UNLOCK`. While locked, the outside `OPEN` button is disabled, but the outside `CLOSE` button remains available if the door is already open. Door and lock state are saved in `dual_monitor_door_state.txt` and restored after reboot.

The current door wiring pins the directly attached top monitor as inside. The outside monitor is connected through the wired modem on the back, so its generated network name (such as `monitor_0`) is selected automatically as the other monitor. The script prints the chosen peripheral names on the computer terminal and labels each screen `INSIDE DOOR` or `OUTSIDE DOOR`:

```lua
local insideMonitorName = "top"
local outsideMonitorName = nil
```

The Redstone Link is attached to the computer's bottom side:

```lua
local redstoneOutputSide = "bottom"
```

This controller assumes sustained power opens the door and removing power closes it; a pulse-driven Sequenced Gearshift needs a different actuator mode.

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

### Vault Storage Dashboard

Path:

```text
scripts/vault-storage/startup.lua
```

Use this on the computer connected to the `3`-high by `7`-wide Advanced Monitor and the wired storage network. It automatically discovers connected inventory peripherals and displays:

- combined item totals on the left, sorted greatest to least, with a signed per-second rate beside each count
- `[SHORT]` / `[LONG]` count formatting, such as `1.5k` or `1,500`
- touchable `^` and `v` item-list scroll buttons
- a `REFRESH` button for an immediate inventory rescan
- a single-row gray footer with pagination right-aligned in the left panel and `[-] FONT: 0.5 [+]` left-aligned in the right panel
- per-storage numbers and fill percentages on the right, using solid fill cells and light-gray empty cells instead of `#`/`-` bar characters
- total network fill at the black bottom of the right panel

The display scans every five seconds and redraws only when the inventory data or displayed rate changes. Each rate is the count difference since the previous scan divided by the real elapsed time: `+20/s` means items were added, `-2.5/s` means items were removed, and the first scan starts at `0/s`. The `REFRESH` button forces an immediate scan. Storage capacity uses one cached `getItemLimit()` lookup per inventory instead of calling it once for every slot.

By default, automatic discovery includes every connected inventory peripheral, including Create vaults and chests. Set `onlyVaultInventories = true` at the top of the script to restore vault-only discovery, or set an exact allowlist:

```lua
local inventoryNames = {
  "create:item_vault_0",
  "create:item_vault_1",
}
```

Leave `inventoryNames` empty to keep automatic discovery.

Do not expose the same inventory through both direct computer adjacency and a wired modem. CC:Tweaked sees those as two peripheral connections and the dashboard will count the inventory twice. Use one connection method per storage structure, or use `inventoryNames` to select exactly the peripheral names that should be counted.

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

Cardinal staircase controller:

```lua
delete startup.lua
wget https://raw.githubusercontent.com/dallen2021/cc-create-plane-controls/main/scripts/cardinal-staircase/startup.lua startup.lua
reboot
```

Eight-way 45-degree staircase controller:

```lua
delete startup.lua
wget https://raw.githubusercontent.com/dallen2021/cc-create-plane-controls/main/scripts/eight-way-staircase/startup.lua startup.lua
reboot
```

Keep `eight_way_staircase_state.txt` during ordinary updates so the controller retains its recorded heading. Only delete it after manually setting the staircase to the configured default heading (SW).

Redstone Link sequencer:

```lua
delete startup.lua
wget https://raw.githubusercontent.com/dallen2021/cc-create-plane-controls/main/scripts/redstone-link-sequencer/startup.lua startup.lua
reboot
```

Bearing monitor controller:

```lua
wget https://raw.githubusercontent.com/dallen2021/cc-create-plane-controls/main/scripts/bearing-monitor/startup.lua startup.lua
reboot
```

Dual-monitor door controller:

```lua
wget https://raw.githubusercontent.com/dallen2021/cc-create-plane-controls/main/scripts/dual-monitor-door/startup.lua startup.lua
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

Vault storage dashboard:

```lua
wget https://raw.githubusercontent.com/dallen2021/cc-create-plane-controls/main/scripts/vault-storage/startup.lua startup.lua
reboot
```

## Create Wiring Notes

For direct peripheral control, the CC:Tweaked computer must see the Sequenced Gearshift as a peripheral. Use either:

- a gearshift directly adjacent to the computer, or
- wired modems plus networking cable.

Wireless modems are useful for computer-to-computer messages, but they do not make a distant Sequenced Gearshift appear as a directly callable peripheral.

For the vault dashboard, use wired modems and networking cable:

```text
3x7 Advanced Monitor
        |
dashboard computer -- wired modem -- networking cable
                                      |-- wired modem -- vault 1
                                      |-- wired modem -- vault 2
                                      `-- wired modem -- vault 3
```

Attach and activate one wired modem for each separate logical vault structure. Do not also place that vault directly against the computer, and do not attach multiple active modems to different blocks of the same merged Create vault. Either setup exposes the same inventory more than once. The monitor can be directly beside the computer or connected through the same wired network.

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

List only visible inventories:

```lua
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.hasType(name, "inventory") then
    print(name, table.concat({ peripheral.getType(name) }, ", "))
  end
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
