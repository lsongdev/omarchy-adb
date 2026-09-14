import QtQuick

// The widget's entry in shell.json, read and written. Which sets are
// configured, which one is active, what the three shortcut buttons launch,
// and the one function that writes any of it back.
//
// Same split as Service.qml: the half that knows how settings are spelled and
// persisted is worth reading without the pad's layout around it. Nothing here
// touches ADB; selecting a set changes `tvAddress`, and Service re-probes on
// its own when that moves.
Item {
  id: cfg

  // From the bar. `settings` is injected after creation, so every read below
  // is a binding rather than something taken once at startup.
  property var bar
  property string moduleName: ""
  property var settings

  // Three is the schema: tv1..tv3 in shell.json, Alt+1..3 to reach them, and
  // three slots is already more TVs than most rooms have. The app shortcut
  // buttons share the count: app1..app3, on keys 1..3.
  readonly property int maxSets: 3

  // Settings keys are spelled in a dozen places across the files. One function
  // per family, so the convention exists once and a caller cannot invent a
  // variant that reads fine and resolves to nothing.
  function tvKey(slot, part)  { return "tv"  + slot + part }
  function appKey(slot, part) { return "app" + slot + part }

  // The manifest's defaults are not merged at runtime (entrySettings hands over
  // exactly what shell.json holds), so every reader carries its own fallback.
  function setting(key, fallback) {
    if (settings && settings[key] !== undefined && settings[key] !== null && settings[key] !== "")
      return settings[key]
    return fallback
  }

  // ---- the configured sets -------------------------------------------------

  // The address configured for a slot, or "". Everything that asks whether a
  // slot is taken goes through here, so the read side cannot disagree with
  // itself.
  function slotAddress(slot) { return setting(tvKey(slot, "Address"), "") }

  // Up to three sets. Slots with no address are dropped rather than listed as
  // dead entries.
  readonly property var tvs: {
    var out = []
    for (var i = 1; i <= maxSets; i++) {
      var addr = slotAddress(i)
      if (addr === "") continue
      out.push({ slot: i, addr: addr, label: setting(tvKey(i, "Label"), "TV " + i) })
    }
    return out
  }

  // Which set the pad is driving, kept as the slot number rather than a
  // position in `tvs`: positions shift the moment a set is removed, slots do
  // not. Seeded from settings so the pad comes back where it was left; the
  // binding is broken by the first switch, which then persists it explicitly.
  property int activeSlot: parseInt(setting("activeSlot", 0), 10) || 0

  // Falls back to the first configured set whenever the remembered slot is not
  // there any more -- exactly what happens after removing the set you were on.
  readonly property int activeIndex: {
    for (var ai = 0; ai < tvs.length; ai++) if (tvs[ai].slot === activeSlot) return ai
    return 0
  }
  readonly property string tvAddress: (tvs.length > activeIndex) ? tvs[activeIndex].addr : ""

  // Lowest slot with no address, or 0 when all three are taken.
  function freeSlot() {
    for (var i = 1; i <= maxSets; i++) if (slotAddress(i) === "") return i
    return 0
  }

  function selectTv(i) {
    if (i < 0 || i >= tvs.length || tvs[i].slot === activeSlot) return
    activeSlot = tvs[i].slot
    persist({ activeSlot: activeSlot })
  }
  function cycleTv() { if (tvs.length > 1) selectTv((activeIndex + 1) % tvs.length) }

  // ---- writing settings back -----------------------------------------------

  // updateEntryInline REPLACES the entry with { id } plus whatever it is handed,
  // so any key omitted here is silently dropped from shell.json -- including the
  // app shortcuts. Always send the current settings merged with the change.
  function persist(patch) {
    if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function") return false
    var merged = ({})
    if (settings) for (var k in settings) if (k !== "id") merged[k] = settings[k]
    for (var q in patch) merged[q] = patch[q]
    return bar.shell.updateEntryInline(moduleName, merged)
  }

  // Writing one slot, used by both the add and the rename paths.
  function writeTv(slot, label, addr) {
    if (slot < 1 || slot > maxSets) return false
    var a = String(addr || "").trim()
    if (a === "") return false
    // A bare IP is what people read off the TV's own network screen; adb needs
    // the port, so fill in the standard one rather than failing the write.
    if (a.indexOf(":") === -1) a += ":5555"
    var name = String(label || "").trim()
    var patch = ({})
    patch[tvKey(slot, "Address")] = a
    patch[tvKey(slot, "Label")] = name === "" ? ("TV " + slot) : name
    return persist(patch)
  }

  function addTv(label, addr) {
    var slot = freeSlot()
    return slot === 0 ? false : writeTv(slot, label, addr)
  }

  function removeTv(slot) {
    if (slot < 1 || slot > maxSets) return false
    var patch = ({})
    patch[tvKey(slot, "Label")] = ""
    patch[tvKey(slot, "Address")] = ""
    if (slot === activeSlot) {
      var next = 0
      for (var i = 0; i < tvs.length; i++) if (tvs[i].slot !== slot) { next = tvs[i].slot; break }
      activeSlot = next
      patch["activeSlot"] = next
    }
    return persist(patch)
  }

  // ---- the shortcut buttons ------------------------------------------------

  // There are no app display names over ADB -- PackageManager hands labels to
  // apps, not to `cmd package` -- so a readable name is guessed from the
  // package. A suggestion, never the app's real name.
  function appName(pkg) {
    var noise = ["com", "org", "net", "tv", "android", "google", "app", "apps",
                 "stable", "livingroom", "one", "main", "mobile"]
    var parts = String(pkg).split(".")
    var best = ""
    for (var i = 0; i < parts.length; i++) {
      if (noise.indexOf(parts[i].toLowerCase()) !== -1) continue
      if (parts[i].length > best.length) best = parts[i]
    }
    return best === "" ? parts[parts.length - 1] : best
  }

  // Same guess, title-cased for reading. The button label derivation uppercases
  // anyway, so the casing only matters where the name is shown as prose.
  function appNiceName(pkg) {
    var n = appName(pkg)
    return n.charAt(0).toUpperCase() + n.slice(1)
  }

  // What a shortcut button says when nobody has named it: the guessed name,
  // cut to fit a key.
  function defaultAppLabel(pkg) { return appName(pkg).substring(0, 4).toUpperCase() }

  function writeApp(slot, label, pkg) {
    if (slot < 1 || slot > maxSets || String(pkg).trim() === "") return false
    var name = String(label || "").trim()
    var patch = ({})
    patch[appKey(slot, "Package")] = String(pkg).trim()
    patch[appKey(slot, "Label")] = name === "" ? defaultAppLabel(pkg) : name
    return persist(patch)
  }
}
