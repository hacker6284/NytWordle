import "support"
import "nytDate"

local HOST <const> = "www.nytimes.com"
local PORT <const> = 443
local USESSL <const> = true
local REASON <const> = "Load today's NYT Wordle"
local HEADERS <const> = {
    ["Accept"] = "application/json",
}

local conn = nil
local body = ""
local settled = false
local requestDate = nil
local onSuccess = nil
local onFailure = nil

local function closeConn()
    if conn ~= nil then
        conn:close()
        conn = nil
    end
end

local function settle(err, solution, printDate)
    if settled then
        return
    end

    settled = true
    closeConn()

    if err ~= nil then
        onFailure(err)
    else
        onSuccess(solution, printDate or requestDate)
    end
end

local function parsePuzzle()
    if body == nil or body == "" then
        return nil, nil, "Empty Wordle response"
    end

    local ok, data = pcall(json.decode, body)

    if not ok or type(data) ~= "table" then
        return nil, nil, "Could not parse Wordle response"
    end

    if type(data.solution) ~= "string" then
        return nil, nil, "Wordle response missing solution"
    end

    local word = string.lower(data.solution)

    if #word ~= letterCount then
        return nil, nil, "Unexpected Wordle solution"
    end

    local printDate = requestDate

    if type(data.print_date) == "string" then
        if data.print_date ~= requestDate then
            return nil, nil, "Wordle returned " .. data.print_date .. " instead of " .. requestDate
        end

        printDate = data.print_date
    end

    return word, printDate, nil
end

local function finishFromBody()
    local word, printDate, err = parsePuzzle()

    if err ~= nil then
        settle(err)
    else
        settle(nil, word, printDate)
    end
end

local function onHeadersRead()
    if conn == nil or settled then
        return
    end

    local status = conn:getResponseStatus()

    if status ~= nil and (status < 200 or status >= 300) then
        settle("HTTP " .. tostring(status))
    end
end

local function onData()
    if conn == nil or settled then
        return
    end

    local available = conn:getBytesAvailable()

    if available > 0 then
        local chunk = conn:read(available)

        if chunk ~= nil and chunk ~= "" then
            body = body .. chunk
        end
    end
end

local function onRequestComplete()
    if conn == nil or settled then
        return
    end

    local err = conn:getError()
    local status = conn:getResponseStatus()

    if status ~= nil and (status < 200 or status >= 300) then
        settle("HTTP " .. tostring(status))
        return
    end

    if err ~= nil and err ~= "Connection closed" then
        settle(err)
        return
    end

    finishFromBody()
end

local function onClosed()
    if settled then
        return
    end

    if body ~= "" then
        finishFromBody()
        return
    end

    local err = nil

    if conn ~= nil then
        err = conn:getError()
    end

    settle(err or "Connection closed")
end

local function abandonInFlight()
    settled = true
    closeConn()
end

function fetchNytWordle(success, failure)
    abandonInFlight()

    onSuccess = success
    onFailure = failure
    settled = false
    body = ""
    requestDate = nytWordleDate()

    playdate.network.setEnabled(true)

    -- http.new yields for the permission dialog, so this must run from playdate.update.
    conn = playdate.network.http.new(HOST, PORT, USESSL, REASON)

    if not conn then
        settle("Network access denied")
        return
    end

    conn:setConnectTimeout(20)
    conn:setReadTimeout(10)
    conn:setHeadersReadCallback(onHeadersRead)
    conn:setRequestCallback(onData)
    conn:setRequestCompleteCallback(onRequestComplete)
    conn:setConnectionClosedCallback(onClosed)

    local path = "/svc/wordle/v2/" .. requestDate .. ".json"
    local queued, getError = conn:get(path, HEADERS)

    if not queued then
        settle(getError or "Could not start Wordle request")
    end
end
