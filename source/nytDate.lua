local EST <const> = -5 * 3600
local EDT <const> = -4 * 3600

local function gmtParts(year, month, day, hour)
    return {
        year = year,
        month = month,
        day = day,
        hour = hour,
        minute = 0,
        second = 0,
        millisecond = 0,
    }
end

local function gmtEpoch(year, month, day, hour)
    return playdate.epochFromGMTTime(gmtParts(year, month, day, hour))
end

-- playdate weekday: 1 = Monday, 7 = Sunday.
local function nthSunday(year, month, n)
    local first = playdate.GMTTimeFromEpoch(gmtEpoch(year, month, 1, 0), 0)
    local firstSunday

    if first.weekday == 7 then
        firstSunday = 1
    else
        firstSunday = 1 + (7 - first.weekday)
    end

    return firstSunday + ((n - 1) * 7)
end

-- US DST, post-2007: 2nd Sunday of March 02:00 EST (07:00 UTC)
-- until 1st Sunday of November 02:00 EDT (06:00 UTC).
local function newYorkOffset(gmt)
    local year = gmt.year
    local now = playdate.epochFromGMTTime(gmt)
    local dstStart = gmtEpoch(year, 3, nthSunday(year, 3, 2), 7)
    local dstEnd = gmtEpoch(year, 11, nthSunday(year, 11, 1), 6)

    if now >= dstStart and now < dstEnd then
        return EDT
    end

    return EST
end

function nytWordleDate(gmt)
    gmt = gmt or playdate.getGMTTime()
    local ny = playdate.GMTTimeFromEpoch(playdate.epochFromGMTTime(gmt) + newYorkOffset(gmt), 0)
    return string.format("%04d-%02d-%02d", ny.year, ny.month, ny.day)
end
