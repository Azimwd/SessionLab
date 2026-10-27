
-- SessionLab Bridge for DMHub
-- Configuration

local SESSIONLAB_URL = "https://sessionlab.up.railway.app"
local SESSIONLAB_TOKEN = "PASTE_NEW_TOKEN_HERE"
local POLL_INTERVAL = 3.0

local currentCursor = "latest"
local pollActive = false
local isPolling = false
local generation = 0
local lastStatus = "Stopped"

-- JSON decoder (no external libraries required)

local function decodeJSON(src)
    if type(src) == "table" then return src end
    assert(type(src) == "string", "Expected JSON string")

    local pos = 1
    local len = #src

    local function skipSpace()
        while pos <= len do
            local c = src:sub(pos, pos)
            if c == " " or c == "\n" or
               c == "\r" or c == "\t" then
                pos = pos + 1
            else
                break
            end
        end
    end

    local function utf8char(cp)
        if cp < 128 then
            return string.char(cp)
        elseif cp < 2048 then
            return string.char(
                192 + math.floor(cp / 64),
                128 + cp % 64
            )
        elseif cp < 65536 then
            return string.char(
                224 + math.floor(cp / 4096),
                128 + math.floor(cp / 64) % 64,
                128 + cp % 64
            )
        elseif cp <= 1114111 then
            return string.char(
                240 + math.floor(cp / 262144),
                128 + math.floor(cp / 4096) % 64,
                128 + math.floor(cp / 64) % 64,
                128 + cp % 64
            )
        end
        error("Invalid Unicode code point")
    end

    local function parseString()
        assert(src:sub(pos, pos) == '"', "Expected quote")
        pos = pos + 1

        local result = {}

        while pos <= len do
            local c = src:sub(pos, pos)
            pos = pos + 1

            if c == '"' then
                return table.concat(result)
            elseif c == "\\" then
                local esc = src:sub(pos, pos)
                pos = pos + 1

                local escapes = {
                    ['"'] = '"',
                    ["\\"] = "\\",
                    ["/"] = "/",
                    ["b"] = "\b",
                    ["f"] = "\f",
                    ["n"] = "\n",
                    ["r"] = "\r",
                    ["t"] = "\t"
                }

                if escapes[esc] then
                    result[#result + 1] = escapes[esc]
                elseif esc == "u" then
                    local hex = src:sub(pos, pos + 3)
                    assert(
                        #hex == 4 and
                        hex:match("^[0-9a-fA-F]+$"),
                        "Invalid Unicode escape"
                    )
                    local cp = tonumber(hex, 16)
                    pos = pos + 4

                    if cp >= 55296 and cp <= 56319 then
                        assert(
                            src:sub(pos, pos + 1) == "\\u",
                            "Missing low surrogate"
                        )
                        pos = pos + 2
                        local lowHex = src:sub(pos, pos + 3)
                        local low = tonumber(lowHex, 16)
                        assert(
                            low and low >= 56320 and low <= 57343,
                            "Invalid low surrogate"
                        )
                        pos = pos + 4
                        cp = 65536 +
                            (cp - 55296) * 1024 +
                            (low - 56320)
                    elseif cp >= 56320 and cp <= 57343 then
                        error("Unexpected low surrogate")
                    end

                    result[#result + 1] = utf8char(cp)
                else
                    error("Invalid JSON escape")
                end
            else
                assert(c:byte() >= 32, "Invalid control character")
                result[#result + 1] = c
            end
        end

        error("Unterminated JSON string")
    end

    local parseValue

    parseValue = function()
        skipSpace()
        local c = src:sub(pos, pos)

        if c == '"' then
            return parseString()
        elseif c == "{" then
            pos = pos + 1
            local result = {}
            skipSpace()

            if src:sub(pos, pos) == "}" then
                pos = pos + 1
                return result
            end

            while true do
                skipSpace()
                local key = parseString()
                skipSpace()

                assert(src:sub(pos, pos) == ":", "Expected colon")
                pos = pos + 1

                result[key] = parseValue()
                skipSpace()

                local sep = src:sub(pos, pos)
                pos = pos + 1

                if sep == "}" then break end
                assert(sep == ",", "Expected comma")
            end

            return result

        elseif c == "[" then
            pos = pos + 1
            local result = {}
            skipSpace()

            if src:sub(pos, pos) == "]" then
                pos = pos + 1
                return result
            end

            while true do
                result[#result + 1] = parseValue()
                skipSpace()

                local sep = src:sub(pos, pos)
                pos = pos + 1

                if sep == "]" then break end
                assert(sep == ",", "Expected comma")
            end

            return result

        elseif src:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true

        elseif src:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false

        elseif src:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil

        else
            local remaining = src:sub(pos)
            local number = remaining:match(
                "^-?%d+%.?%d*[eE]?[+-]?%d*"
            )
            assert(number and tonumber(number), "Invalid JSON value")
            pos = pos + #number
            return tonumber(number)
        end
    end

    local result = parseValue()
    skipSpace()
    assert(pos > len, "Trailing JSON data")
    return result
end

-- Helpers

local function notify(message)
    chat.Send("[SessionLab] " .. tostring(message))
end

local function updateStatus(message)
    if lastStatus ~= message then
        lastStatus = message
        -- Network and parser diagnostics belong in the local console, not
        -- the shared game chat. /slbridge status is available on demand.
        print("SessionLab Bridge: " .. message)
    end
end

local function shortText(value)
    local text = tostring(value or "Unknown error")
    return text:gsub("[\r\n]", " "):sub(1, 200)
end

local function sendEvent(ev)
    local raw = tostring(ev.text or "")
    if raw == "" then return end

    -- The newer feed provides these presentation fields. Older servers only
    -- provide text, so split the same already-saved result as a fallback.
    local actor = ev.actor
    local title = ev.title
    local summary = ev.summary
    if type(actor) ~= "string" or type(title) ~= "string" then
        actor, title, summary = raw:match("^(.-): (.-) — (.+)$")
        if not actor then
            actor, title = raw:match("^(.-): (.+)$")
            summary = ""
        end
    end
    actor = actor or "SessionLab"
    title = title or "Бросок"
    summary = summary or raw
    -- Never send a /roll command here: DMHub would roll again and disagree
    -- with the authoritative SessionLab result.
    local body = actor .. (summary ~= "" and "\n" .. summary or "")
    if ExtChatMessage ~= nil and
       type(ExtChatMessage.SendTitled) == "function" then
        local color = ev.kind == "ability" and "#9085FF" or "#45CBA6"
        local ok, err = pcall(
            ExtChatMessage.SendTitled,
            body, title, color, dmhub.userid
        )
        if ok then return end
        updateStatus("Titled chat unavailable: " .. shortText(err))
    end
    chat.Send(title .. "\n" .. body)
end

-- Polling

local pollSessionLab

local function scheduleNext(runId)
    dmhub.Schedule(POLL_INTERVAL, function()
        if pollActive and generation == runId then
            pollSessionLab(runId)
        end
    end)
end

pollSessionLab = function(runId)
    if not pollActive or generation ~= runId or isPolling then
        return
    end

    isPolling = true

    local url = string.format(
        "%s/api/integrations/dmhub/events/?cursor=%s",
        SESSIONLAB_URL,
        tostring(currentCursor)
    )

    local function finish()
        if generation ~= runId then return end
        isPolling = false
        if pollActive then scheduleNext(runId) end
    end

    local function onSuccess(body)
        if generation ~= runId then return end

        local ok, response = pcall(decodeJSON, body)
        if not ok or type(response) ~= "table" then
            updateStatus("JSON error: " .. shortText(response))
            finish()
            return
        end

        -- SessionLab returns {data = {events = {...}, cursor = N}, error = null}.
        if response.error ~= nil then
            updateStatus("API error: " .. shortText(response.error))
            finish()
            return
        end
        local payload = response.data
        if type(payload) ~= "table" or type(payload.events) ~= "table" then
            updateStatus("Unexpected API response: missing data.events")
            finish()
            return
        end

        updateStatus("API connected")
        for _, ev in ipairs(payload.events) do
            if type(ev) == "table" then
                if type(ev.text) == "string" and ev.text ~= "" then
                    sendEvent(ev)
                end
                if ev.id ~= nil then
                    currentCursor = tostring(ev.id)
                end
            end
        end
        -- Also advance after cursor=latest and empty responses.
        if payload.cursor ~= nil then
            currentCursor = tostring(payload.cursor)
        end
        finish()
    end

    local function onFailure(err)
        if generation ~= runId then return end
        updateStatus("HTTP error: " .. shortText(err))
        finish()
    end

    local ok, err = pcall(function()
        net.Get({
            url = url,
            headers = {
                ["Authorization"] = "Bearer " .. SESSIONLAB_TOKEN,
                ["Accept"] = "application/json"
            },
            success = onSuccess,
            failure = onFailure
        })
    end)

    if not ok then onFailure(err) end
end

-- Controls

local function startBridge()
    if pollActive then
        notify("Bridge already running")
        return
    end

    if SESSIONLAB_TOKEN == "" or
       SESSIONLAB_TOKEN == "PASTE_NEW_TOKEN_HERE" then
        notify("Configure SESSIONLAB_TOKEN first")
        return
    end

    generation = generation + 1
    pollActive = true
    isPolling = false
    currentCursor = "latest"
    lastStatus = "Connecting"

    print("SessionLab Bridge: started")
    pollSessionLab(generation)
end

local function stopBridge()
    generation = generation + 1
    pollActive = false
    isPolling = false
    lastStatus = "Stopped"
    print("SessionLab Bridge: stopped")
end

local function bridgeStatus()
    notify(
        "Bridge: " .. (pollActive and "ON" or "OFF") ..
        " | Status: " .. lastStatus ..
        " | Cursor: " .. currentCursor
    )
end

-- Chat command

Commands.slbridge = function(args)
    local action = tostring(args or ""):lower()
    action = action:match("^%s*(.-)%s*$")

    if action == "stop" then
        stopBridge()
    elseif action == "status" then
        bridgeStatus()
    elseif action == "restart" then
        stopBridge()
        startBridge()
    elseif action == "" or action == "start" then
        startBridge()
    else
        notify("Usage: /slbridge [stop|status|restart]")
    end
end

print("SessionLab Bridge loaded")
