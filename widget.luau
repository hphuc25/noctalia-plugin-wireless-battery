--!nonstrict
-- Wireless Battery: adds wireless mice, keyboards, headsets, gamepads and phones
-- to the bar, right next to the built-in battery widget. Visuals mirror that
-- widget: glyph + percentage, cyan bolt while charging, red when low.
--
-- The "devices" setting is a list of filters. A device is shown when any filter
-- matches its kind ("mouse", "headset", "keyboard", "gamepad", "phone", "other")
-- or a case-insensitive substring of its name, key or connection. Empty = all.
-- Several matching devices are shown at the same time.
--
-- visibility: dynamic hides the widget when no device is connected;
--             static keeps it visible and shows "<glyph> ?".
--
-- A sleeping mouse still appears in `--json` with percent = -1: its last real
-- level is shown for `grace` seconds. A device that disappears from the poll
-- (receiver unplugged / switched off) is dropped immediately so no stale
-- percentage is left on the bar.
--
-- Left-click opens a detail panel; right-click forces a refresh.

local PANEL_ID = "hphuc25/wireless-battery:devices"
local LOW_THRESHOLD = 15

local GLYPHS = {
    mouse    = "mouse",
    headset  = "headphones",
    keyboard = "keyboard",
    gamepad  = "device-gamepad-2",
    phone    = "device-mobile",
    other    = "devices",
}

local cmd        = noctalia.getConfig("command") or "wireless-battery"
local interval   = tonumber(noctalia.getConfig("interval")) or 60
local mode       = noctalia.getConfig("mode") or "all"
local visibility = noctalia.getConfig("visibility") or "dynamic"
local filters    = noctalia.getConfig("device_filters") or {}
local grace      = tonumber(noctalia.getConfig("grace")) or 1800

local cacheDir = noctalia.pluginDataDir()
local cachePath = cacheDir and (cacheDir .. "/last-devices.json") or nil
local lastKnown = {}

local devices = {}
local busy = false
local missing = false

local function lower(s)
    return string.lower(type(s) == "string" and s or "")
end

local function contains(haystack, needle)
    return string.find(lower(haystack), needle, 1, true) ~= nil
end

local function matchesFilter(device, filter)
    local f = lower(noctalia.string.trim(filter))
    if f == "" or f == "*" or f == "all" then return true end
    if lower(device.kind) == f then return true end
    if contains(device.name, f) then return true end
    if contains(device.key, f) then return true end
    if contains(device.via, f) then return true end
    return false
end

local function isSelected(device)
    if type(filters) ~= "table" or #filters == 0 then return true end
    for _, filter in ipairs(filters) do
        if matchesFilter(device, filter) then return true end
    end
    return false
end

local function staticGlyph()
    if type(filters) == "table" then
        for _, filter in ipairs(filters) do
            local f = lower(noctalia.string.trim(filter))
            if GLYPHS[f] then return GLYPHS[f] end
        end
    end
    return "mouse"
end

local function copyDevice(d)
    return {
        key        = d.key,
        name       = d.name,
        via        = d.via,
        kind       = d.kind,
        percent    = d.percent,
        level      = d.level,
        detail     = d.detail,
        charging   = d.charging,
        asleep     = d.asleep,
        connected  = d.connected,
        millivolts = d.millivolts,
        graceSec   = d.graceSec,
    }
end

local function loadCache()
    if not cachePath then return end
    local raw = noctalia.readFile(cachePath)
    if not raw then return end
    local ok, data = pcall(noctalia.json.decode, raw)
    if not ok or type(data) ~= "table" then return end
    for _, entry in ipairs(data) do
        if type(entry) == "table" and type(entry.key) == "string"
            and type(entry.device) == "table" then
            lastKnown[entry.key] = { device = entry.device, time = tonumber(entry.time) or 0 }
        end
    end
end

local function saveCache()
    if not cachePath then return end
    local out = {}
    for key, entry in pairs(lastKnown) do
        out[#out + 1] = { key = key, device = entry.device, time = entry.time }
    end
    local encoded = noctalia.json.encode(out)
    if encoded then noctalia.writeFile(cachePath, encoded) end
end

-- Keep the last level for a sleeping/temporarily missing device.
local function withLastKnown(data)
    local now = os.time()
    local result = {}
    local present = {}

    for _, raw in ipairs(data) do
        local d = copyDevice(raw)
        local key = d.key
        if key ~= nil then present[key] = true end

        if d.connected == false then
            lastKnown[key] = nil
        else
            if d.percent ~= nil and d.percent >= 0 then
                lastKnown[key] = { device = copyDevice(d), time = now }
            else
                -- Device is still reported by its receiver but gave no level: use the
                -- last real reading for `grace` seconds. Do NOT extend the timestamp,
                -- otherwise a sleeping mouse would stay stale forever.
                local cached = lastKnown[key]
                local limit = tonumber(d.graceSec) or grace
                if cached and now - cached.time <= limit then
                    d.percent    = cached.device.percent
                    d.level      = cached.device.level
                    d.detail     = cached.device.detail
                    d.kind       = d.kind or cached.device.kind
                    d.name       = (d.name ~= nil and d.name ~= "") and d.name or cached.device.name
                    d.via        = (d.via ~= nil and d.via ~= "") and d.via or cached.device.via
                    d.charging   = false
                    d.asleep     = true
                    d.connected  = true
                end
            end
            result[#result + 1] = d
        end
    end

    -- A device missing from this poll is gone (receiver unplugged / device off):
    -- drop its cached level immediately instead of showing a stale percentage.
    for key in pairs(lastKnown) do
        if not present[key] then lastKnown[key] = nil end
    end

    saveCache()
    return result
end

local function levelText(device)
    if device.percent ~= nil and device.percent >= 0 then
        return tostring(device.percent) .. "%"
    end
    if device.level ~= nil and device.level ~= "" then
        return device.level
    end
    return "?"
end

local function isVisible(device)
    if device.connected == false then return false end
    if device.percent == nil and (device.level == nil or device.level == "") then return false end
    return isSelected(device)
end

local function isLow(device)
    return device.percent ~= nil and device.percent >= 0
        and device.percent <= LOW_THRESHOLD and not device.charging
end

local function opaccent(device)
    if device.charging then return "primary" end
    if isLow(device) then return "error" end
    return nil
end

local function shownDevices()
    local list = {}
    for _, device in ipairs(devices) do
        if isVisible(device) then list[#list + 1] = device end
    end
    if mode ~= "lowest" or #list <= 1 then return list end
    table.sort(list, function(a, b)
        local pa = a.percent or 101
        local pb = b.percent or 101
        if pa ~= pb then return pa < pb end
        return (a.name or "") < (b.name or "")
    end)
    return { list[1] }
end

local function tooltipRows()
    local rows = {}
    for _, device in ipairs(devices) do
        if isVisible(device) then
            local text = levelText(device)
            if device.charging then text = text .. " · " .. noctalia.tr("status.charging") end
            if device.asleep then text = text .. " · " .. noctalia.tr("status.asleep") end
            rows[#rows + 1] = { key = device.name or device.key or "?", value = text }
        end
    end
    if #rows == 0 then
        rows[1] = { key = noctalia.tr("panel.title"), value = noctalia.tr("tooltip.empty") }
    end
    return rows
end

local function render()
    if missing then
        barWidget.render(ui.row({ gap = 6, align = "center" }, {
            ui.glyph({ name = "alert-triangle", size = 14, color = "error" }),
            ui.label({ text = "no cli", color = "error" }),
        }))
        barWidget.setTooltip(noctalia.tr("panel.missing"))
        return
    end

    local shown = shownDevices()
    if #shown == 0 then
        if visibility == "static" then
            barWidget.render(ui.row({ gap = 4, align = "center" }, {
                ui.glyph({ name = staticGlyph(), size = 14, color = "on_surface_variant" }),
                ui.label({ text = "?", color = "on_surface_variant" }),
            }))
            barWidget.setTooltip(tooltipRows())
            return
        end
        -- Dynamic: stay invisible so the built-in battery widget is unchanged.
        barWidget.render(ui.row({ gap = 0 }, {}))
        barWidget.setTooltip({})
        return
    end

    local items = {}
    for _, device in ipairs(shown) do
        local color = opaccent(device)
        local row = {
            ui.glyph({ name = GLYPHS[device.kind] or GLYPHS.other, size = 14, color = color }),
            ui.label({ text = levelText(device), color = color }),
        }
        if device.charging then
            row[#row + 1] = ui.glyph({ name = "bolt", size = 12, color = "primary" })
        end
        items[#items + 1] = ui.row({ key = device.key, gap = 4, align = "center" }, row)
    end

    local container = barWidget.isVertical() and ui.column or ui.row
    barWidget.render(container({ gap = 8, align = "center" }, items))
    barWidget.setTooltip(tooltipRows())
end

local function refresh()
    if busy then return end
    busy = true
    local started = noctalia.runAsync({ cmd, "--json" }, function(result)
        busy = false
        if result.exitCode ~= 0 then
            noctalia.log("wireless-battery: exit " .. tostring(result.exitCode) .. ": "
                .. tostring(result.stderr))
            return
        end
        local data, err = noctalia.json.decode(result.stdout)
        if type(data) ~= "table" then
            noctalia.log("wireless-battery: bad JSON: " .. tostring(err))
            return
        end
        missing = false
        devices = withLastKnown(data)
        noctalia.state.set("devices", devices)
        render()
    end)
    if not started then busy = false end
end

function update()
    refresh()
end

function onClick()
    noctalia.togglePanel(PANEL_ID)
end

function onRightClick()
    refresh()
end

function onIpc(event)
    if event == "refresh" then refresh() end
end

function onConfigChanged()
    cmd        = noctalia.getConfig("command") or "wireless-battery"
    interval   = tonumber(noctalia.getConfig("interval")) or 60
    mode       = noctalia.getConfig("mode") or "all"
    visibility = noctalia.getConfig("visibility") or "dynamic"
    filters    = noctalia.getConfig("device_filters") or {}
    grace      = tonumber(noctalia.getConfig("grace")) or 1800
    missing    = not noctalia.commandExists(cmd)
    noctalia.setUpdateInterval(interval * 1000)
    render()
    refresh()
end

noctalia.setUpdateInterval(interval * 1000)
loadCache()

if not noctalia.commandExists(cmd) then
    missing = true
end
render()
refresh()
