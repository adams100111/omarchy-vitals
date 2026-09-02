import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Vitals: a configurable row of resource readouts in the bar, each an icon
// plus its current value, that switches to an alert style once it crosses a
// per-resource threshold. The popup lists every resource and lets each one be
// pinned to or hidden from the bar individually.
Panel {
  id: root

  moduleName: "dev.vitals"
  ipcTarget: "dev.vitals"

  readonly property bool vertical: bar ? bar.vertical === true : false
  readonly property int barSize: bar ? bar.barSize : Style.space(26)

  implicitWidth: vertical ? barSize : contentWidth + Style.space(10)
  implicitHeight: vertical ? contentHeight + Style.space(8) : barSize

  readonly property real contentWidth: chips.length > 0 ? layout.implicitWidth : placeholder.implicitWidth
  readonly property real contentHeight: chips.length > 0 ? layout.implicitHeight : placeholder.implicitHeight

  // Canonical display order, used when a resource is pinned back on.
  readonly property var metricOrder: ["cpu", "memory", "swap", "disk", "temp", "network"]

  // ------------------------------------------------------- setting access
  // Toggling from the popup should redraw immediately rather than waiting for
  // shell.json to round-trip, so a local override shadows `settings` until the
  // reloaded config arrives.
  property var overrideSettings: null
  onSettingsChanged: overrideSettings = null

  readonly property var effective: overrideSettings !== null ? overrideSettings : (settings || ({}))

  function cfg(name, fallback) {
    var value = effective ? effective[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // `omarchy bar set` stores values as strings, while the settings UI and a
  // hand-edited shell.json store real types. Accept both.
  function asList(value, fallback) {
    if (value === undefined || value === null) return fallback
    if (Array.isArray(value)) return value
    if (typeof value === "object" && typeof value.length === "number") {
      // A QVariantList crossing the QML boundary is array-like but can fail
      // Array.isArray, so copy it out by index.
      var copied = []
      for (var c = 0; c < value.length; c++) copied.push(String(value[c]))
      return copied
    }
    if (typeof value === "string") {
      var text = value.trim()
      if (text === "") return fallback
      if (text.charAt(0) === "[") {
        try {
          var parsed = JSON.parse(text)
          if (Array.isArray(parsed)) return parsed
        } catch (e) {
          // Fall through to comma splitting.
        }
      }
      var parts = text.split(",").map(function(x) { return x.trim() })
      return parts.filter(function(x) { return x.length > 0 })
    }
    return fallback
  }

  function asInt(value, fallback) {
    var n = Number(value)
    return isFinite(n) ? Math.round(n) : fallback
  }

  function asBool(value, fallback) {
    return Style.boolToken(value, fallback)
  }

  function warnAt(key, fallback) {
    return asInt(cfg(key, fallback), fallback)
  }

  // ------------------------------------------------------------- settings
  // An absent `metrics` key means "use the defaults"; an explicitly empty list
  // means the user hid everything, which is a legitimate state.
  readonly property var chosen: {
    var raw = cfg("metrics", null)
    if (raw === null) return ["memory", "disk"]
    return asList(raw, [])
  }

  readonly property bool showIcons: asBool(cfg("showIcons", true), true)
  readonly property bool showUnits: asBool(cfg("showUnits", true), true)
  readonly property string diskPath: String(cfg("diskPath", "/") || "/")
  readonly property string alertStyle: String(cfg("alertStyle", "Color and bold") || "Color and bold")
  readonly property int intervalSec: Math.max(1, asInt(cfg("intervalSec", 3), 3))

  readonly property color alertColor: bar && bar.urgent ? bar.urgent : Color.urgent
  readonly property bool alertColors: alertStyle.indexOf("Color") >= 0
  readonly property bool alertBold: alertStyle.indexOf("old") >= 0
  readonly property bool alertDot: alertStyle.indexOf("dot") >= 0

  function isPinned(key) {
    return chosen.indexOf(key) >= 0
  }

  // The metrics list as actually persisted, which is what the IPC surface
  // should report even if this instance was handed stale settings.
  function storedMetrics() {
    var config = (bar && bar.shell) ? bar.shell.shellConfig : null
    if (config) {
      var entry = findEntry(config)
      if (entry) return entryMetrics(entry)
    }
    return chosen
  }

  // --------------------------------------------------------- persistence
  // Locate this widget's own entry in the shell config. The id can appear more
  // than once (allowMultiple), so fall back to matching stored settings.
  function findEntry(config) {
    if (!config || !config.bar || !config.bar.layout) return null

    var sections = ["left", "center", "right"]
    var matches = []
    for (var s = 0; s < sections.length; s++) {
      var list = config.bar.layout[sections[s]]
      if (!Array.isArray(list)) continue
      for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].id === root.moduleName) matches.push(list[i])
      }
    }

    if (matches.length === 0) return null
    if (matches.length === 1) return matches[0]

    var mine = JSON.stringify(root.settings || ({}))
    for (var m = 0; m < matches.length; m++) {
      var copy = {}
      for (var key in matches[m]) if (key !== "id") copy[key] = matches[m][key]
      if (JSON.stringify(copy) === mine) return matches[m]
    }
    return matches[0]
  }

  function applySettings(patch) {
    var merged = {}
    for (var a in root.effective) merged[a] = root.effective[a]
    for (var b in patch) merged[b] = patch[b]
    root.overrideSettings = merged

    if (bar && bar.shell && typeof bar.shell.mutateShellConfig === "function") {
      bar.shell.mutateShellConfig(function(config) {
        var entry = root.findEntry(config)
        if (!entry) return
        for (var c in patch) entry[c] = patch[c]
      })
      return
    }

    // Fallback for a bar that does not expose the shell: the CLI stores
    // strings, which the coercion helpers above already tolerate.
    if (!bar) return
    for (var d in patch) {
      var value = patch[d]
      var text = (typeof value === "string") ? value : JSON.stringify(value)
      bar.run("omarchy bar set " + root.moduleName + " " + d + " " + Util.shellQuote(text))
    }
  }

  // Read the metrics list as stored on a config entry, applying the
  // "absent means defaults, empty means nothing" rule.
  function entryMetrics(entry) {
    var raw = (entry && entry.metrics !== undefined && entry.metrics !== null) ? entry.metrics : null
    if (raw === null) return ["memory", "disk"]
    return asList(raw, [])
  }

  function noteOptimistic(patch) {
    var merged = {}
    for (var a in root.effective) merged[a] = root.effective[a]
    for (var b in patch) merged[b] = patch[b]
    root.overrideSettings = merged
  }

  // `mutate` receives the currently stored metrics and returns a settings
  // patch. Reading the stored list inside the mutation keeps every caller --
  // a popup click or an IPC call from any instance -- working off one truth.
  function applyMetricsMutation(mutate) {
    if (bar && bar.shell && typeof bar.shell.mutateShellConfig === "function") {
      bar.shell.mutateShellConfig(function(config) {
        var entry = root.findEntry(config)
        if (!entry) return
        var patch = mutate(root.entryMetrics(entry))
        if (!patch) return
        for (var k in patch) entry[k] = patch[k]
        root.noteOptimistic(patch)
      })
      return
    }
    var fallbackPatch = mutate(root.chosen.slice())
    if (fallbackPatch) root.applySettings(fallbackPatch)
  }

  function insertInOrder(list, key) {
    var next = list.slice()
    if (next.indexOf(key) >= 0) return next
    var rank = root.metricOrder.indexOf(key)
    var insertAt = next.length
    for (var i = 0; i < next.length; i++) {
      if (root.metricOrder.indexOf(next[i]) > rank) { insertAt = i; break }
    }
    next.splice(insertAt, 0, key)
    return next
  }

  // Pin or hide one resource. Re-pinning restores it at its canonical position
  // relative to whatever is already showing, so the bar order stays stable.
  function toggleMetric(key) {
    root.applyMetricsMutation(function(current) {
      var at = current.indexOf(key)
      if (at >= 0) {
        var next = current.slice()
        next.splice(at, 1)
        return { metrics: next }
      }
      return { metrics: root.insertInOrder(current, key) }
    })
  }

  function setMetricPinned(key, pinned) {
    root.applyMetricsMutation(function(current) {
      var has = current.indexOf(key) >= 0
      if (has === pinned) return null
      if (!pinned) {
        var next = current.slice()
        next.splice(next.indexOf(key), 1)
        return { metrics: next }
      }
      return { metrics: root.insertInOrder(current, key) }
    })
  }

  // Clicking a filesystem either hides the disk readout or points it at that
  // mount, so the popup doubles as the mount picker.
  function toggleDisk(mount) {
    var currentPath = root.diskPath
    root.applyMetricsMutation(function(current) {
      if (current.indexOf("disk") >= 0 && mount === currentPath) {
        var next = current.slice()
        next.splice(next.indexOf("disk"), 1)
        return { metrics: next }
      }
      return { metrics: root.insertInOrder(current, "disk"), diskPath: mount }
    })
  }

  // --------------------------------------------------------------- sample
  property var sample: ({})
  property bool hasSample: false

  readonly property var disks: sample.disks ? sample.disks : []
  readonly property var primaryDisk: {
    for (var i = 0; i < disks.length; i++) if (disks[i].mount === diskPath) return disks[i]
    return disks.length > 0 ? disks[0] : null
  }

  readonly property string helperPath: decodeURIComponent(
    String(Qt.resolvedUrl("vitals-sample")).replace("file://", ""))

  // ---------------------------------------------------------- formatting
  function pctOf(used, total) {
    return total > 0 ? (used * 100 / total) : 0
  }

  function fmtPct(value) {
    return Math.round(value) + (root.showUnits ? "%" : "")
  }

  function fmtBytes(bytes) {
    if (!bytes || bytes < 0) return "0 B"
    var units = ["B", "K", "M", "G", "T"]
    var i = 0
    var v = bytes
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
    return (v >= 100 || i === 0 ? Math.round(v) : v.toFixed(1)) + units[i]
  }

  function fmtSize(bytes) {
    if (!bytes || bytes < 0) return "0 B"
    var units = ["B", "KiB", "MiB", "GiB", "TiB"]
    var i = 0
    var v = bytes
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
    return (i === 0 ? Math.round(v) : v.toFixed(1)) + " " + units[i]
  }

  // ------------------------------------------------------------ bar chips
  readonly property var chips: {
    var out = []
    if (!root.hasSample) return out

    for (var i = 0; i < root.chosen.length; i++) {
      var key = root.chosen[i]

      if (key === "cpu") {
        var cpu = (root.sample.cpu || 0) / 10
        out.push({ icon: "\uf2db", text: root.fmtPct(cpu), warn: cpu >= root.warnAt("cpuWarnPct", 85) })

      } else if (key === "memory") {
        var mem = root.pctOf(root.sample.memUsed, root.sample.memTotal)
        out.push({ icon: "\uf0e4", text: root.fmtPct(mem), warn: mem >= root.warnAt("memoryWarnPct", 85) })

      } else if (key === "swap") {
        var swap = root.pctOf(root.sample.swapUsed, root.sample.swapTotal)
        out.push({ icon: "\uf0ec", text: root.fmtPct(swap), warn: swap >= root.warnAt("swapWarnPct", 50) })

      } else if (key === "disk") {
        if (root.primaryDisk) {
          var disk = root.primaryDisk.pct / 10
          out.push({ icon: "\uf0a0", text: root.fmtPct(disk), warn: disk >= root.warnAt("diskWarnPct", 85) })
        }

      } else if (key === "temp") {
        var t = root.sample.temp
        if (t !== undefined && t >= 0) {
          out.push({ icon: "\uf2c7", text: Math.round(t) + (root.showUnits ? "°C" : ""),
                     warn: t >= root.warnAt("tempWarnC", 80) })
        }

      } else if (key === "network") {
        out.push({ icon: "\uf019", text: root.fmtBytes(root.sample.rx || 0), warn: false })
        out.push({ icon: "\uf093", text: root.fmtBytes(root.sample.tx || 0), warn: false })
      }
    }
    return out
  }

  // -------------------------------------------------------- popup details
  // Every resource is listed whether or not it is pinned, so anything hidden
  // can be brought back from here.
  readonly property var details: {
    var rows = []
    if (!root.hasSample) return rows

    var cpu = (root.sample.cpu || 0) / 10
    rows.push({ key: "cpu", mount: "", label: "CPU", value: Math.round(cpu) + "%",
                pct: cpu, warn: cpu >= root.warnAt("cpuWarnPct", 85),
                pinned: root.isPinned("cpu") })

    var memPct = root.pctOf(root.sample.memUsed, root.sample.memTotal)
    rows.push({ key: "memory", mount: "", label: "Memory",
                value: root.fmtSize(root.sample.memUsed) + " / " + root.fmtSize(root.sample.memTotal)
                       + "  ·  " + root.fmtSize(root.sample.memAvail) + " free",
                pct: memPct, warn: memPct >= root.warnAt("memoryWarnPct", 85),
                pinned: root.isPinned("memory") })

    if (root.sample.swapTotal > 0) {
      var swapPct = root.pctOf(root.sample.swapUsed, root.sample.swapTotal)
      rows.push({ key: "swap", mount: "", label: "Swap",
                  value: root.fmtSize(root.sample.swapUsed) + " / " + root.fmtSize(root.sample.swapTotal),
                  pct: swapPct, warn: swapPct >= root.warnAt("swapWarnPct", 50),
                  pinned: root.isPinned("swap") })
    }

    for (var i = 0; i < root.disks.length; i++) {
      var d = root.disks[i]
      var dp = d.pct / 10
      rows.push({ key: "disk", mount: d.mount, label: d.mount,
                  value: root.fmtSize(d.used) + " / " + root.fmtSize(d.total)
                         + "  ·  " + root.fmtSize(d.avail) + " free",
                  pct: dp, warn: dp >= root.warnAt("diskWarnPct", 85),
                  pinned: root.isPinned("disk") && d.mount === root.diskPath })
    }

    if (root.sample.temp !== undefined && root.sample.temp >= 0) {
      rows.push({ key: "temp", mount: "", label: "Temperature",
                  value: Math.round(root.sample.temp) + " °C", pct: -1,
                  warn: root.sample.temp >= root.warnAt("tempWarnC", 80),
                  pinned: root.isPinned("temp") })
    }

    rows.push({ key: "network", mount: "", label: "Network",
                value: "\uf019 " + root.fmtBytes(root.sample.rx || 0) + "/s"
                       + "    \uf093 " + root.fmtBytes(root.sample.tx || 0) + "/s",
                pct: -1, warn: false, pinned: root.isPinned("network") })
    return rows
  }

  // ------------------------------------------------------------- sampling
  Process {
    id: sampler
    command: [root.helperPath, root.diskPath]
    stdout: SplitParser {
      onRead: function(line) {
        if (!line || line.length === 0) return
        try {
          root.sample = JSON.parse(line)
          root.hasSample = true
        } catch (e) {
          // A partial or malformed line just means we keep the last good sample.
        }
      }
    }
  }

  function refresh() {
    if (!sampler.running) sampler.running = true
  }

  Timer {
    interval: root.intervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ------------------------------------------------------------ bar layout
  Grid {
    id: layout
    anchors.centerIn: parent
    visible: root.chips.length > 0
    columns: root.vertical ? 1 : chipRepeater.count
    rows: root.vertical ? chipRepeater.count : 1
    columnSpacing: Style.space(9)
    rowSpacing: Style.space(2)

    Repeater {
      id: chipRepeater
      model: root.chips

      Row {
        id: chip
        spacing: Style.space(4)

        readonly property bool warn: modelData.warn === true
        readonly property color tint: warn && root.alertColors ? root.alertColor : root.barForeground

        Text {
          visible: root.showIcons && modelData.icon !== ""
          text: modelData.icon
          color: chip.tint
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: chip.warn && root.alertBold
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: modelData.text + (chip.warn && root.alertDot ? " •" : "")
          color: chip.tint
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: chip.warn && root.alertBold
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }

  // Keeps the widget clickable when every resource is hidden, so the popup
  // stays reachable to turn them back on.
  Text {
    id: placeholder
    anchors.centerIn: parent
    visible: root.chips.length === 0
    text: "\uf2db"
    color: root.barForeground
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  MouseArea {
    id: clickTarget
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
      } else if (mouse.button === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.toggle()
      }
    }
  }

  // --------------------------------------------------------------- popup
  KeyboardPanel {
    id: popup
    anchorItem: clickTarget
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    centerOnBar: false
    contentWidth: popup.fittedContentWidth(Style.space(420))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
    }

    Column {
      id: content
      width: parent.width
      spacing: Style.space(8)

      Text {
        text: "System vitals"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        text: "Click a row to show or hide it in the bar"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.details

        Rectangle {
          id: row
          width: content.width
          implicitHeight: rowContent.implicitHeight + Style.space(8)
          radius: Style.space(4)

          readonly property bool warn: modelData.warn === true
          readonly property bool pinned: modelData.pinned === true
          readonly property color tint: warn ? Color.urgent : Color.popups.text

          color: rowMouse.containsMouse
            ? Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.08)
            : "transparent"

          Behavior on color { ColorAnimation { duration: 120 } }

          Column {
            id: rowContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(3)

            Item {
              width: parent.width
              implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

              Text {
                id: eye
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                // Checked box when pinned to the bar, empty box when hidden.
                text: row.pinned ? "\uf046" : "\uf096"
                color: row.pinned ? (row.warn ? Color.urgent : Color.accent) : Color.muted
                opacity: row.pinned ? 1.0 : 0.7
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                id: labelText
                anchors.left: eye.right
                anchors.leftMargin: Style.space(7)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: row.pinned ? row.tint : Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: row.warn
                elide: Text.ElideMiddle
                width: Math.min(implicitWidth, parent.width * 0.42)
              }

              Text {
                id: valueText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.value
                color: row.warn ? Color.urgent : Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }

            Rectangle {
              visible: modelData.pct >= 0
              width: parent.width
              height: Math.max(2, Style.space(3))
              radius: height / 2
              color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.12)

              Rectangle {
                width: parent.width * Math.max(0, Math.min(100, modelData.pct)) / 100
                height: parent.height
                radius: parent.radius
                color: row.warn ? Color.urgent : Color.accent
                opacity: row.pinned ? 1.0 : 0.5
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
              }
            }
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (modelData.key === "disk") root.toggleDisk(modelData.mount)
              else root.toggleMetric(modelData.key)
            }
          }
        }
      }

      Text {
        text: "Right click the bar opens btop  ·  middle click refreshes"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        width: content.width
        wrapMode: Text.WordWrap
      }
    }
  }

  // Scriptable equivalents of the popup toggles, so resources can be pinned
  // from a keybinding: `omarchy-shell dev.vitals.metrics toggle cpu`.
  IpcHandler {
    target: "dev.vitals.metrics"

    function list(): string {
      return JSON.stringify(root.storedMetrics())
    }

    function available(): string {
      return JSON.stringify(root.metricOrder)
    }

    function toggle(key: string): string {
      if (root.metricOrder.indexOf(key) < 0) return "unknown metric: " + key
      root.toggleMetric(key)
      return JSON.stringify(root.storedMetrics())
    }

    function show(key: string): string {
      if (root.metricOrder.indexOf(key) < 0) return "unknown metric: " + key
      root.setMetricPinned(key, true)
      return JSON.stringify(root.storedMetrics())
    }

    function hide(key: string): string {
      if (root.metricOrder.indexOf(key) < 0) return "unknown metric: " + key
      root.setMetricPinned(key, false)
      return JSON.stringify(root.storedMetrics())
    }

    function mount(path: string): string {
      root.toggleDisk(path)
      return root.diskPath
    }
  }
}
