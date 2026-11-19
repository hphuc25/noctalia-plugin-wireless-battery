--!nonstrict
-- Wireless Battery: detail panel styled like Noctalia's built-in Power tab.
-- Each connected peripheral gets its own bordered card: glyph, name, level,
-- connection details and a progress bar. Header and close button mirror the
-- Power panel too.
--
-- The bar widget publishes the latest snapshot on `noctalia.state`, so the
-- panel opens with data already in place and refreshes itself in the background.

local GLYPHS = {
    mouse    = "mouse",
    headset  = "headphones",
    keyboard = "keyboard",
    gamepad  = "device-gamepad-2",
    phone    = "device-mobile",
    other    = "devices",
}

local BORDER = "outline_variant/0.6"

local INSTALL_URL = "https://github.com/krisgfx9/Wireless-Device-Battery-Monitor"

local cmd     = noctalia.getConfig("command") or "wireless-battery"
local filters = noctalia.getConfig("device_filters") or {}

local devices = {}
local cliMissing = false
local open = false
local busy = false

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

local function levelText(device)
    if device.percent ~= nil and device.percent >= 0 then
        return tostring(device.percent) .. "%"
    end
    if device.level ~= nil and device.level ~= "" then
        return device.level
    end
    return "?"
end

local function subtitle(device)
    local parts = {}
    if device.via ~= nil and device.via ~= "" then parts[#parts + 1] = device.via end
    if device.detail ~= nil and device.detail ~= "" then parts[#parts + 1] = device.detail end
    if device.asleep then parts[#parts + 1] = noctalia.tr("status.asleep") end
    if device.charging then parts[#parts + 1] = noctalia.tr("status.charging") end
    return table.concat(parts, " · ")
end

local function accent(device)
    if device.charging then return "primary" end
    if device.percent ~= nil and device.percent >= 0
        and device.percent <= 15 then return "error" end
    return "on_surface"
end

local function deviceCard(device)
    local color = accent(device)
    local valueRow = {
        ui.label({ text = levelText(device), fontWeight = "bold", fontSize = 14, color = color }),
    }
    if device.charging then
        valueRow[#valueRow + 1] = ui.glyph({ name = "bolt", size = 13, color = "primary" })
    end

    local children = {
        ui.row({ align = "center", justify = "space_between" }, {
            ui.row({ gap = 8, align = "center" }, {
                ui.glyph({ name = GLYPHS[device.kind] or GLYPHS.other, size = 16, color = color }),
                ui.label({
                    text = device.name or device.key or "?",
                    fontWeight = "bold",
                    fontSize = 13,
                    maxLines = 1,
                }),
            }),
            ui.row({ gap = 5, align = "center" }, valueRow),
        }),
    }

    local sub = subtitle(device)
    local hasProgress = device.percent ~= nil and device.percent >= 0

    -- Divider between the device header and its details, like the Monitor card.
    if sub ~= "" or hasProgress then
        children[#children + 1] = ui.separator({ color = BORDER, thickness = 1 })
    end

    if sub ~= "" then
        children[#children + 1] = ui.label({
            text = sub,
            fontSize = 11,
            color = "on_surface_variant",
            maxLines = 1,
        })
    end

    if hasProgress then
        -- Noctalia's own battery card uses a Surface track with a fully rounded radius.
        children[#children + 1] = ui.row({
            radius = 4,
            border = "outline_variant/0.5",
            borderWidth = 1,
            padding = 1,
        }, {
            ui.progress({
                progress = math.clamp(device.percent / 100, 0, 1),
                height = 6,
                radius = 3,
                fill = color,
                flexGrow = 1,
                track = "surface",
            }),
        })
    end

    return ui.column({
        key = device.key,
        gap = 9,
        padding = 13,
        radius = 12,
        fill = "surface_container",
        border = BORDER,
        borderWidth = 1,
    }, children)
end

local function missingCard()
    return ui.column({
        gap = 10,
        padding = 13,
        radius = 12,
        fill = "surface_container",
        border = BORDER,
        borderWidth = 1,
    }, {
        ui.label({
            text = noctalia.tr("panel.cli_title"),
            fontWeight = "bold",
            fontSize = 13,
            color = "error",
        }),
        ui.label({
            text = noctalia.tr("panel.missing", { url = INSTALL_URL }),
            fontSize = 11,
            color = "on_surface_variant",
            maxLines = 4,
        }),
        ui.button({
            text = noctalia.tr("panel.cli_action"),
            variant = "primary",
            controlSize = "sm",
            onClick = "onOpenGuide",
        }),
    })
end

local function render()
    if cliMissing then
        panel.render(ui.column({ gap = 12, padding = 14, flexGrow = 1 }, {
            ui.row({ align = "center", justify = "space_between" }, {
                ui.label({ text = noctalia.tr("panel.title"), fontWeight = "bold", fontSize = 16 }),
                ui.button({
                    glyph = "x",
                    variant = "ghost",
                    controlSize = "sm",
                    tooltip = noctalia.tr("panel.close"),
                    onClick = "onCloseButton",
                }),
            }),
            missingCard(),
        }))
        return
    end

    local cards = {}
    for _, device in ipairs(devices) do
        if device.connected ~= false and isSelected(device) then
            cards[#cards + 1] = deviceCard(device)
        end
    end

    if #cards == 0 then
        cards[1] = ui.column({
            gap = 8,
            padding = 13,
            radius = 12,
            fill = "surface_container",
            border = BORDER,
            borderWidth = 1,
        }, {
            ui.label({
                text = noctalia.tr("panel.empty"),
                fontSize = 12,
                color = "on_surface_variant",
                maxLines = 3,
            }),
        })
    end

    panel.render(ui.column({ gap = 12, padding = 14, flexGrow = 1 }, {
        ui.row({ align = "center", justify = "space_between" }, {
            ui.label({ text = noctalia.tr("panel.title"), fontWeight = "bold", fontSize = 16 }),
            ui.button({
                glyph = "x",
                variant = "ghost",
                controlSize = "sm",
                tooltip = noctalia.tr("panel.close"),
                onClick = "onCloseButton",
            }),
        }),
        ui.scroll({ flexGrow = 1, gap = 10 }, cards),
    }))
end

local function refresh()
    if busy then return end
    busy = true
    noctalia.runAsync({ cmd, "--json" }, function(result)
        busy = false
        if result.exitCode ~= 0 then
            noctalia.log("wireless-battery: exit " .. tostring(result.exitCode) .. ": "
                .. tostring(result.stderr))
            return
        end
        local data = noctalia.json.decode(result.stdout)
        if type(data) ~= "table" then return end
        devices = data
        noctalia.state.set("devices", data)
        if open then render() end
    end)
end

function onRefresh()
    refresh()
end

function onCloseButton()
    panel.close()
end

function onOpenGuide()
    noctalia.runAsync({ "xdg-open", INSTALL_URL })
end

function onConfigChanged()
    cmd     = noctalia.getConfig("command") or "wireless-battery"
    filters = noctalia.getConfig("device_filters") or {}
    if open then render() end
end

function onOpen()
    open = true
    local cached = noctalia.state.get("devices")
    if type(cached) == "table" then devices = cached end
    cliMissing = noctalia.state.get("cli_missing") == true
    render()
    if not cliMissing then refresh() end
end

function onClose()
    open = false
end

noctalia.state.watch("devices", function(value)
    if type(value) ~= "table" then return end
    devices = value
    if open then render() end
end)

noctalia.state.watch("cli_missing", function(value)
    cliMissing = value == true
    if open then render() end
end)
