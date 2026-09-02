# Vitals

A Vitals-style resource readout for the Omarchy bar. Pick which resources show
inline — each drawn as an icon with its value and unit — and each switches to an
alert style once it crosses its own threshold. Click the widget for the full
breakdown, and click any row there to pin or hide that resource.

Requires Omarchy 4 (Quattro) or newer.

## Install

```bash
omarchy plugin add https://github.com/adams100111/omarchy-vitals.git --enable
```

Then place it wherever you like:

```bash
omarchy bar move adams100111.vitals --section right
```

## Showing and hiding resources

Click the widget to open the popup. Every resource is listed there whether or
not it is currently in the bar:

- A checked box means it is pinned to the bar.
- An empty box, dimmed, means it is hidden.
- Click a row to toggle it. Re-pinning restores it to its canonical position,
  so the bar order stays stable.
- Clicking a filesystem row points the inline disk readout at that mount, or
  hides it if that mount is already the one being shown.

Hiding everything is allowed; the widget keeps a single icon so the popup stays
reachable.

The same toggles are scriptable, which makes them bindable to a key:

```bash
omarchy-shell adams100111.vitals.metrics list            # what is pinned now
omarchy-shell adams100111.vitals.metrics available       # every resource key
omarchy-shell adams100111.vitals.metrics toggle cpu
omarchy-shell adams100111.vitals.metrics show network
omarchy-shell adams100111.vitals.metrics hide swap
omarchy-shell adams100111.vitals.metrics mount /home     # point the disk readout elsewhere
omarchy-shell adams100111.vitals open                    # open the popup
```

Note that new IPC targets only register on a full `omarchy restart shell`;
editing plugin QML hot-reloads the widget but not its IPC surface.

## Settings

Set these on the widget's entry in `~/.config/omarchy/shell.json` (it
hot-reloads on save), or with `omarchy bar set adams100111.vitals <key> <value>`.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `metrics` | list | `["memory","disk"]` | Which resources show inline, in display order. Any of `cpu`, `memory`, `swap`, `disk`, `temp`, `network`. An empty list shows none. |
| `intervalSec` | int | `3` | Seconds between samples. |
| `showIcons` | bool | `true` | Draw the icon next to each value. |
| `showUnits` | bool | `true` | Append `%` / `°C`. |
| `diskPath` | string | `/` | Which filesystem the inline disk readout tracks. |
| `alertStyle` | enum | `Color and bold` | `Color`, `Bold`, `Color and bold`, or `Color and dot`. |
| `cpuWarnPct` | int | `85` | Alert once CPU is above this. |
| `memoryWarnPct` | int | `85` | Alert once memory used is above this (85 = warn under 15% free). |
| `swapWarnPct` | int | `50` | Alert once swap used is above this. |
| `diskWarnPct` | int | `85` | Alert once disk used is above this (85 = warn under 15% free). |
| `tempWarnC` | int | `80` | Alert once CPU temperature is above this. |

Example:

```json
{ "id": "adams100111.vitals",
  "metrics": ["memory", "disk", "network"],
  "diskPath": "/home",
  "memoryWarnPct": 80,
  "alertStyle": "Color and bold" }
```

`allowMultiple` is on, so a second `adams100111.vitals` entry can watch a different
mount in another bar section.

## Interaction

| Gesture | Effect |
|---|---|
| Left click the bar | Open or close the popup |
| Left click a popup row | Pin or hide that resource |
| Right click the bar | Open btop |
| Middle click the bar | Resample immediately |
| `Esc` | Close the popup |

## Layout

- `vitals-sample` — emits one JSON line of metrics, reading `/proc/stat`,
  `/proc/meminfo`, `/sys/class/net`, `/sys/class/hwmon` and `df`. CPU and
  network are rates, so previous counters live in
  `$XDG_RUNTIME_DIR/omarchy-vitals.state`.
- `Panel.qml` — bar chips, threshold styling, the detail popup, and the
  toggle/persistence logic.
- `manifest.json` — the settings schema that drives Omarchy's settings UI.

Implementation notes:

- Percentages cross the shell boundary as tenths of a percent so one decimal
  survives.
- Filesystems are deduplicated by device, so Btrfs subvolumes are listed once.
- Setting values are coerced on read: `omarchy bar set` stores strings while the
  settings UI and a hand-edited `shell.json` store real JSON types, and both work.
- Toggles are computed from the persisted config rather than from injected
  settings, so a popup click and an IPC call always agree.

## License

MIT
