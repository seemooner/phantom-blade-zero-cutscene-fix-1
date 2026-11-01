-- CutsceneFix for Phantom Blade Zero (UE4SS Lua mod)
-- Local reviewed revision: exact URL matching, transactional source edits,
-- deferred success cache, and bounded handling of incomplete codec metadata.
--
-- Some pre-rendered cutscenes in Content/Movies are 4K60 H.264 at level 5.2, which is above
-- what the Windows H.264 decoder officially supports (level 5.1). On affected PCs they stay
-- black while the audio plays. The game already ships a 1080p copy of every movie in
-- Content/MoviesHalfRes (used when the game runs at 1080p or lower).
--
-- This mod checks videos as they open. Only when a video exceeds MAX_H264_LEVEL does it
-- redirect it to the same file in MoviesHalfRes. Everything else is left alone.
--
-- Event-driven: nothing runs until a video finishes opening
-- (PBZMediaImageAspectBinder:HandleMediaOpened) or a new media player is created. Then just that player is
-- watched for up to WATCH_SECONDS, and the watcher stops as soon as it has been checked.
-- Files found to be bad are remembered in known_bad.txt and redirected straight away next time.

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local MAX_H264_LEVEL  = 5.1    -- swap anything above this
local POLL_MS         = 50     -- check interval, only while a video is being watched
local WATCH_SECONDS   = 6      -- how long to watch a player after a trigger
local RESYNC          = true   -- seek the half-res copy to where the original "should" be
local GIVE_UP_SECONDS = 3      -- if the half-res copy isn't ready by then, stop trying
local VERBOSE         = false  -- log triggers and every video checked, not just swaps

---------------------------------------------------------------------------
local function log(msg) print("[CutsceneFix] " .. tostring(msg) .. "\n") end

local function str(v)
    if v == nil then return "" end
    if type(v) == "string" then return v end
    local ok, s = pcall(function() return v:ToString() end)
    return ok and s or tostring(v)
end

local function call(obj, method, ...)
    local args = { ... }
    local ok, res = pcall(function() return obj[method](obj, table.unpack(args)) end)
    if ok then return res end
    return nil
end

local players  = {}   -- address -> MediaPlayer (every player we've seen)
local states   = {}   -- address -> per-video state
local watching = {}   -- address -> tick at which to stop watching
local watchCount = 0
local tick     = 0    -- watch-loop counter, used as a clock
local busy, loopRunning = false, false

local function addrOf(obj)
    local ok, addr = pcall(function() return obj:GetAddress() end)
    return ok and addr or nil
end

local function track(mp)
    local addr = addrOf(mp)
    if addr then players[addr] = mp end
    return addr
end

local function secondsSince(t) return (tick - t) * POLL_MS / 1000 end
local function ticksFor(seconds) return math.ceil(seconds * 1000 / POLL_MS) end

---------------------------------------------------------------------------
-- Remembered bad files (known_bad.txt in the mod folder)
---------------------------------------------------------------------------
local knownBad = {}
local KNOWN_BAD_PATH = (function()
    local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
    local dir = src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]+$")
    return dir and (dir .. "/known_bad.txt") or nil
end)()

local function loadKnownBad()
    if not KNOWN_BAD_PATH then return end
    local ok, f = pcall(io.open, KNOWN_BAD_PATH, "r")
    if not ok or not f then return end
    for line in f:lines() do
        local name = line:match("^%s*(.-)%s*$")
        if name ~= "" then knownBad[name] = true end
    end
    f:close()
end

local function rememberBad(name)
    if knownBad[name] or not KNOWN_BAD_PATH then return end
    knownBad[name] = true
    local ok, f = pcall(io.open, KNOWN_BAD_PATH, "a")
    if ok and f then f:write(name .. "\n") f:close() end
end

local function codecTooHigh(mp)
    local codec = str(call(mp, "GetVideoTrackType", 0, 0))
    if codec == "" then return nil, codec end      -- not known yet
    if not (codec:lower():find("avc", 1, true) or codec:find("264", 1, true)) then return false, codec end
    local level = tonumber(codec:match("[Ll]evel%s*([%d%.]+)"))
    if level == nil then return nil, codec end -- incomplete metadata: retry within watch window
    return level > MAX_H264_LEVEL, codec
end

local function shortName(url) return url:match("([^/\\]+)$") or url end
local function normalizedUrl(url) return url:gsub("\\", "/") end

---------------------------------------------------------------------------
-- Media sources: find the object the game opens from, and point it at MoviesHalfRes
---------------------------------------------------------------------------
local SOURCE_CLASSES = { "PBZStreamMediaSource", "StreamMediaSource", "FileMediaSource",
                         "PlatformMediaSource", "MediaSource" }

local function allSources()
    local seen, out = {}, {}
    for _, cn in ipairs(SOURCE_CLASSES) do
        local ok, list = pcall(FindAllOf, cn)
        if ok and list then
            for _, s in pairs(list) do
                local okA, a = pcall(function() return s:GetAddress() end)
                local okV, v = pcall(function() return s:IsValid() end)
                if okA and okV and v and not seen[a] then
                    seen[a] = true
                    table.insert(out, s)
                end
            end
        end
    end
    return out
end

-- Calls fn(propName, propType) for every property of obj's class and its parents
local function forEachProp(obj, fn)
    local okC, s = pcall(function() return obj:GetClass() end)
    if not okC then return end
    for _ = 1, 12 do
        local okV, v = pcall(function() return s:IsValid() end)
        if not (okV and v) then return end
        pcall(function()
            s:ForEachProperty(function(p)
                local okN, name = pcall(function() return p:GetFName():ToString() end)
                local okT, ptype = pcall(function() return p:GetClass():GetFName():ToString() end)
                if okN and okT then fn(name, ptype) end
            end)
        end)
        local okS, sup = pcall(function() return s:GetSuperStruct() end)
        if not okS or sup == nil then return end
        s = sup
    end
end

local function describe(src)
    log("  source " .. str(call(src, "GetFullName")) .. "  GetUrl = " .. str(call(src, "GetUrl")))
    forEachProp(src, function(name, ptype)
        local ok, v = pcall(function() return src[name] end)
        local val = not ok and "?" or (type(v) == "boolean" and tostring(v)) or str(v)
        log(string.format("    %-14s %s = %s", ptype, name, val))
    end)
end

local function toHalfRes(s)
    -- "…/Movies/…" or "Movies/…" -> MoviesHalfRes (an existing MoviesHalfRes is left alone)
    local out, n = s:gsub("^Movies([/\\])", "MoviesHalfRes%1", 1)
    if n == 0 then out, n = s:gsub("([/\\])Movies([/\\])", "%1MoviesHalfRes%2", 1) end
    return out, n > 0
end

-- Returns (source, newUrl) on success, or nil
local function redirectSources(playerUrl)
    if playerUrl == "" then return nil end
    local targetUrl = normalizedUrl(playerUrl)
    local matches = {}
    for _, src in ipairs(allSources()) do
        if normalizedUrl(str(call(src, "GetUrl"))) == targetUrl then table.insert(matches, src) end
    end

    if #matches == 0 then
        log("No media source with that file found. Sources currently loaded:")
        for i, src in ipairs(allSources()) do
            if i > 15 then break end
            log("  " .. str(call(src, "GetFullName")) .. " -> " .. str(call(src, "GetUrl")))
        end
        return nil
    end

    for _, src in ipairs(matches) do
        local before = str(call(src, "GetUrl"))
        local edits = {}
        local function rollback()
            for _, edit in ipairs(edits) do
                local ok, err = pcall(function()
                    -- Do not overwrite a subsequent change made by the game.
                    if str(src[edit.name]) == edit.after then src[edit.name] = edit.before end
                end)
                if not ok then log("Source rollback failed: " .. tostring(err)) end
            end
        end
        forEachProp(src, function(name, ptype)
            if ptype ~= "StrProperty" then return end
            local ok, v = pcall(function() return str(src[name]) end)
            if not ok or normalizedUrl(v) ~= normalizedUrl(before) then return end
            local newV, changed = toHalfRes(v)
            if changed then
                local okSet, err = pcall(function() src[name] = newV end)
                if okSet then table.insert(edits, {name=name, before=v, after=newV}) end
                log(string.format("  %s.%s: %s -> %s %s", str(call(src, "GetFName")), name, v, newV,
                    okSet and "" or ("(FAILED: " .. tostring(err) .. ")")))
            end
        end)
        local after = str(call(src, "GetUrl"))
        if after ~= before and after:find("MoviesHalfRes", 1, true) then
            return src, after, rollback
        end
        rollback()
        log("Rewrite didn't change the source's URL. Its properties:")
        describe(src)
    end
    return nil
end

local function checkPlayer(addr, mp)
    local url = str(call(mp, "GetUrl"))
    local st = states[addr]
    if url == "" then
        if st and st.pending and st.rollback then st.rollback() end
        states[addr] = nil
        return
    end
    if st == nil or (url ~= st.url and url ~= st.halfUrl) then
        if st and st.pending and st.rollback then st.rollback() end
        st = { url = url, first = tick, swaps = 0 }
        states[addr] = st
    end

    if st.pending and secondsSince(st.swappedAt) > GIVE_UP_SECONDS then
        log("Half-res playback timed out: " .. shortName(url))
        if st.rollback then st.rollback() end
        st.pending, st.gaveUp = false, true
        return
    end

    -- Our half-res copy is loading / playing
    if st.halfUrl ~= nil and url == st.halfUrl then
        if st.pending then
            if call(mp, "IsReady") then
                if not call(mp, "IsPlaying") and call(mp, "Play") ~= true then return end
                if RESYNC then
                    local target = math.floor(secondsSince(st.first) * 10000000)
                    local ok, sought = pcall(function() return mp:Seek({ Ticks = target }) end)
                    if not ok or sought ~= true then log("Resync seek failed; video may lag the audio") end
                end
                st.pending, st.checked = false, true
                rememberBad(shortName(st.url))
                st.rollback = nil
                log("Half-res copy playing: " .. shortName(url))
            end
        end
        return
    end

    -- Original file
    if st.pending then return end -- OpenSource may accept before GetUrl changes
    if st.checked or st.gaveUp then return end
    if not normalizedUrl(url):find("/Content/Movies/", 1, true) then st.checked = true return end

    local tooHigh, codec
    if knownBad[shortName(url)] then
        -- Seen before: redirect immediately, without waiting for the decoder to report
        tooHigh, codec = true, "known bad"
    else
        if not call(mp, "IsReady") then return end
        tooHigh, codec = codecTooHigh(mp)
        if tooHigh == nil then return end
        if VERBOSE then log(shortName(url) .. ": " .. codec) end
    end

    if not tooHigh then st.checked = true return end
    if st.swaps >= 2 then
        log("Game keeps reopening the original; leaving it alone: " .. shortName(url))
        st.gaveUp = true
        return
    end

    log(string.format("%s is %s - redirecting its media source to the half-res copy", shortName(url), codec))
    st.swaps = st.swaps + 1

    local src, newUrl, rollback = redirectSources(url)
    if src == nil then
        log("Couldn't redirect the source; leaving this video alone (details above).")
        st.gaveUp = true
        return
    end

    st.halfUrl, st.pending, st.swappedAt = newUrl, true, tick
    st.rollback = rollback
    -- Reopen from the (now redirected) source, so the game's own check sees a match
    if call(mp, "OpenSource", src) ~= true then
        rollback()
        st.pending, st.gaveUp = false, true
        log("OpenSource rejected the half-res copy; source restored: " .. shortName(url))
    end
end

---------------------------------------------------------------------------
-- Watcher: runs only while something is being watched, then stops itself
---------------------------------------------------------------------------
local function stopWatching(addr)
    if watching[addr] then
        watching[addr] = nil
        watchCount = watchCount - 1
    end
end

local function poll()
    tick = tick + 1
    for addr, untilTick in pairs(watching) do
        local mp = players[addr]
        local okv, valid = pcall(function() return mp:IsValid() end)
        if not (okv and valid) then
            local st = states[addr]
            if st and st.pending and st.rollback then st.rollback() end
            players[addr], states[addr] = nil, nil
            stopWatching(addr)
        else
            local ok, err = pcall(checkPlayer, addr, mp)
            if not ok then log("Error: " .. tostring(err)) end
            local st = states[addr]
            local pending = st ~= nil and st.pending
            local done = st ~= nil and (st.checked or st.gaveUp) and not pending
            if done then
                stopWatching(addr)
            elseif tick >= untilTick and not pending then
                local url = str(call(mp, "GetUrl"))
                if url ~= "" then
                    log("Watch expired without a decision: " .. url .. " ready=" ..
                        tostring(call(mp, "IsReady")) .. " codec=" .. str(call(mp, "GetVideoTrackType", 0, 0)))
                end
                stopWatching(addr)
            end
        end
    end
end

local function startLoop()
    if loopRunning then return end
    loopRunning = true
    LoopAsync(POLL_MS, function()
        if watchCount <= 0 and not busy then
            loopRunning = false
            if VERBOSE then log("Watcher idle") end
            return true -- stop looping
        end
        if not busy then
            busy = true
            ExecuteInGameThread(function()
                local ok, err = pcall(poll)
                if not ok then log("Poll error: " .. tostring(err)) end
                busy = false
            end)
        end
        return false
    end)
end

local function watch(mp, why)
    local addr = track(mp)
    if not addr then return end
    if not watching[addr] then watchCount = watchCount + 1 end
    watching[addr] = tick + ticksFor(WATCH_SECONDS)
    local st = states[addr]
    if st and not st.pending then states[addr] = nil end -- re-check from scratch
    if VERBOSE then log("Watching player (" .. why .. ")") end
    startLoop()
end

local function watchAllKnown(why)
    for _, mp in pairs(players) do watch(mp, why) end
end

---------------------------------------------------------------------------
-- Triggers
---------------------------------------------------------------------------
-- Pull a MediaPlayer out of a hooked function's parameters, if there is one
local function playerFromParams(params)
    for _, p in ipairs(params) do
        local ok, v = pcall(function() return p:get() end)
        if ok and type(v) == "userdata" then
            local okC, cn = pcall(function() return v:GetClass():GetFName():ToString() end)
            if okC and cn then
                if cn:find("MediaPlayer") then return v end
                if cn:find("MediaTexture") then
                    local mp = call(v, "GetMediaPlayer")
                    if mp ~= nil then return mp end
                end
            end
        end
    end
    return nil
end

-- The binder object usually holds a reference to the player it's attached to
local function playerFromBinder(binder)
    local found = nil
    forEachProp(binder, function(name, ptype)
        if found or ptype ~= "ObjectProperty" then return end
        local ok, v = pcall(function() return binder[name] end)
        if ok and type(v) == "userdata" then
            local okC, cn = pcall(function() return v:GetClass():GetFName():ToString() end)
            if okC and cn and cn:find("MediaPlayer") then found = v end
        end
    end)
    return found
end

local function playerFromUrl(url)
    if url == "" then return nil end
    local targetUrl = normalizedUrl(url)
    for _, mp in pairs(players) do
        if normalizedUrl(str(call(mp, "GetUrl"))) == targetUrl then return mp end
    end
    return nil
end

-- Unreal's "media opened" event, as handled by the game's video binder. Event handlers are
-- always invoked through reflection, so this fires even though the game opens videos from C++.
local OPEN_HOOKS = {
    "/Script/ProjectPBZ.PBZMediaImageAspectBinder:HandleMediaOpened",
}

local function registerHooks()
    local ok_count = 0
    for _, path in ipairs(OPEN_HOOKS) do
        local ok = pcall(RegisterHook, path, function(ctx, ...)
            local params = { ... }
            local mp = playerFromParams(params)
            if mp == nil then
                local okB, binder = pcall(function() return ctx:get() end)
                if okB and binder then mp = playerFromBinder(binder) end
            end
            if mp == nil and params[1] ~= nil then
                local okU, url = pcall(function() return str(params[1]:get()) end)
                if okU and url ~= "" then mp = playerFromUrl(url) end
            end
            if mp then watch(mp, "media opened") else watchAllKnown("media opened") end
        end)
        if ok then ok_count = ok_count + 1 end
    end
    return ok_count
end

-- New players: track and watch them briefly
NotifyOnNewObject("/Script/MediaAssets.MediaPlayer", function(mp) watch(mp, "new player") end)

-- Players that already exist: just remember them (no watching until a trigger)
ExecuteInGameThread(function()
    local list = FindAllOf("MediaPlayer")
    if list then for _, mp in pairs(list) do track(mp) end end
end)

loadKnownBad()
local hooked = registerHooks()
if hooked == 0 then
    log("WARNING: couldn't hook the game's media-opened handler; only newly created players will be checked.")
end

local n = 0
for _ in pairs(knownBad) do n = n + 1 end
log(string.format("Loaded reviewed revision 1. Redirecting H.264 videos above level %s to MoviesHalfRes (%d known bad file%s, %d hook%s).",
    MAX_H264_LEVEL, n, n == 1 and "" or "s", hooked, hooked == 1 and "" or "s"))

