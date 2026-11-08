-- CutsceneFix for Phantom Blade Zero (UE4SS Lua mod)
--
-- Some pre-rendered cutscenes in Content/Movies are 4K60 H.264 at level 5.2, which is above
-- what the Windows H.264 decoder officially supports (level 5.1). On affected PCs they stay
-- black while the audio plays. The game already ships a 1080p copy of every movie in
-- Content/MoviesHalfRes (used when the game runs at 1080p or lower).
--
-- This mod checks videos as they open. Only when a video exceeds MAX_H264_LEVEL does it
-- redirect it to the same file in MoviesHalfRes. Everything else is left alone.
--
-- 1.4.1: every story cutscene in the game (66, read from its Movie paks) is level 5.2 with a level 4.2 copy, so
-- they are switched by name as soon as the mod sees them, without waiting for the decoder to report a level (a
-- decoder that refuses the video, or Proton, which names no level, never does). The level check stays for videos a
-- game update may add. A video that fails to open is switched from the address the failure reports.
--
-- Event-driven: nothing runs until a video finishes opening
-- (PBZMediaImageAspectBinder:HandleMediaOpened) or a new media player is created. Then just that player is
-- watched for up to WATCH_SECONDS, and the watcher stops as soon as it has been checked.
-- Files found to be bad are remembered in known_bad.txt and redirected straight away next time.

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
-- Enabled, Resync and DetailedLog are set in CutsceneFix.config.json (and the PBZ Mods Menu); these are the defaults.
local ENABLED         = true
local MAX_H264_LEVEL  = 5.1    -- swap anything above this
local RESYNC          = true   -- seek the half-res copy to where the original "should" be
local VERBOSE         = false  -- log triggers and every video checked, not just swaps
local POLL_MS         = 50     -- check interval, only while a video is being watched
local WATCH_SECONDS   = 6      -- how long to watch a player after a trigger
local GIVE_UP_SECONDS = 3      -- if the half-res copy isn't ready by then, stop trying

---------------------------------------------------------------------------
local function log(msg) print("[CutsceneFix] " .. tostring(msg) .. "\n") end

local MOD_DIR = (function()
    local src = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
    return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]+$")
end)()
local MC = dofile(MOD_DIR .. "/scripts/pbz_menuconfig.lua")
local cfg = MC.config("CutsceneFix", MOD_DIR,
    { Enabled = true, Resync = true, DetailedLog = false },
    { "Enabled", "Resync", "DetailedLog" }, nil, log)

local function applyConfig()
    local v = cfg:load()
    ENABLED = v.Enabled ~= false
    RESYNC = v.Resync ~= false
    VERBOSE = v.DetailedLog == true
end
applyConfig()

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

-- No game object is kept between frames: a destroyed player's memory can be reused or released, and touching it
-- then crashes UE4SS outright (1.3.0 and 1.4.1 kept every player they had seen; a crash at the Loong Pillar).
-- Each poll looks the players up afresh; only their addresses, as plain numbers, key the per-video state.
local states   = {}   -- address -> per-video state
local watchUntil = 0  -- tick at which the watcher stops (unless a switch is still pending)
local failedUrl       -- a video the game reported as failed to open, to be switched on the next poll
local tick     = 0    -- watch-loop counter, used as a clock
local busy, loopRunning = false, false

local function addrOf(obj)
    local ok, addr = pcall(function() return obj:GetAddress() end)
    return ok and addr or nil
end

local function secondsSince(t) return (tick - t) * POLL_MS / 1000 end
local function ticksFor(seconds) return math.ceil(seconds * 1000 / POLL_MS) end

---------------------------------------------------------------------------
-- Remembered bad files (known_bad.txt in the mod folder)
---------------------------------------------------------------------------
local knownBad = {}
-- Every story cutscene in the game: 4K H.264 at level 5.2, each with a level 4.2 copy in MoviesHalfRes (read from the
-- game's Movie paks, build of November 2026: 66 of the 400 videos). These switch as soon as the mod sees them, without
-- waiting for the decoder to report a level: a decoder that refuses the video, or (Proton) names no level, never would.
local BUILTIN_BAD = {
    "2D_DuanHun_g04_ShiFu_1080p_30FPS.mp4",
    "2D_LuJiaCun_g02_jichengren_1080p.mp4",
    "2D_PangZhen_g03_shaonian_1080p.mp4",
    "2Dmix+CGguishou.mp4",
    "3DCG_C02_JieMeng.mp4",
    "3DCG_C03_XianZheYunLuo.mp4",
    "3DCG_C04_MoBao-variant1.mp4",
    "3DCG_C05_MoBao-variant2.mp4",
    "3DCG_C06_MoBao-variant3.mp4",
    "3DCG_C07_MoBao.mp4",
    "3DCG_C08_MoBao-variant4.mp4",
    "Chapter01_2026.7.20.mp4",
    "Chapter02_2026.7.20.mp4",
    "Chapter03_2026.7.20.mp4",
    "Chapter04_2026.7.20.mp4",
    "Chapter05_2026.7.20.mp4",
    "Chapter06_2026.7.20.mp4",
    "Chapter07_2026.7.20.mp4",
    "Chapter08_2026.7.20.mp4",
    "DEMO_CN_logo.mp4",
    "DEMO_EN_logo.mp4",
    "EasyDifficulty.mp4",
    "Ending_Juezhan_Alpha.mp4",
    "Ending_Juezhan_Alpha_EN.mp4",
    "Ending_Juezhan_RGB.mp4",
    "Ending_Juezhan_RGB_EN.mp4",
    "Ending_Longyin_Alpha.mp4",
    "Ending_Longyin_Alpha_EN.mp4",
    "Ending_Longyin_RGB.mp4",
    "Ending_Longyin_RGB_EN.mp4",
    "Ending_Yanmie_Alpha.mp4",
    "Ending_Yanmie_Alpha_EN.mp4",
    "Ending_Yanmie_RGB.mp4",
    "Ending_Yanmie_RGB_EN.mp4",
    "Ending_Yinhen_Alpha.mp4",
    "Ending_Yinhen_Alpha_EN.mp4",
    "Ending_Yinhen_RGB.mp4",
    "Ending_Yinhen_RGB_EN.mp4",
    "HardDifficulty.mp4",
    "NightMareDifficulty.mp4",
    "NormalDifficulty.mp4",
    "PBZlogo-EN_Alpha.mp4",
    "PBZlogo-EN_RGB.mp4",
    "PBZlogo_Alpha.mp4",
    "PBZlogo_RGB.mp4",
    "PlaceHolder1.mp4",
    "PlaceHolder2.mp4",
    "PlaceHolder3.mp4",
    "Seq004_Render_1080p.mp4",
    "Seq018-mask_Render_1080p.mp4",
    "Seq018_cam11render.mp4",
    "Seq148_render.mp4",
    "Seq152_recap.mp4",
    "Seqmashup_bossrecap.mp4",
    "Seqs001_Render.mp4",
    "Seqs002_Render.mp4",
    "Seqs013_cam8render.mp4",
    "Seqs019-flash_render_H265.mp4",
    "Seqs020_render.mp4",
    "Seqs021flash001_render.mp4",
    "Seqs024_mashup.mp4",
    "StartScreen_16x9.mp4",
    "s017_rendercut_H265.mp4",
    "seq051_012cut.mp4",
    "seqs007_cam1-3Render_1080p.mp4",
    "seqs013_cam1-3render.mp4",
}
local builtinBad = {}
for _, n in ipairs(BUILTIN_BAD) do builtinBad[n:lower()] = true end
local function isKnownBad(name)
    return knownBad[name] or builtinBad[name:lower()] == true
end
local KNOWN_BAD_PATH = MOD_DIR and (MOD_DIR .. "/known_bad.txt") or nil

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
    if knownBad[name] or builtinBad[name:lower()] or not KNOWN_BAD_PATH then return end
    knownBad[name] = true
    local ok, f = pcall(io.open, KNOWN_BAD_PATH, "a")
    if ok and f then f:write(name .. "\n") f:close() end
end

local function codecTooHigh(mp)
    local codec = str(call(mp, "GetVideoTrackType", 0, 0))
    if codec == "" then return nil, codec end      -- not known yet
    if not (codec:find("AVC") or codec:find("264")) then return false, codec end
    local level = tonumber(codec:match("[Ll]evel%s*([%d%.]+)"))
    return level ~= nil and level > MAX_H264_LEVEL, codec
end

local function shortName(url) return url:match("([^/\\]+)$") or url end

local function videoHeight(mp)
    local d = call(mp, "GetVideoTrackDimensions", 0, 0)
    if d == nil then return nil end
    local ok, y = pcall(function() return d.Y end)
    return ok and tonumber(y) or nil
end

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
function redirectSources(playerUrl)
    local file = shortName(playerUrl)
    local matches = {}
    for _, src in ipairs(allSources()) do
        if str(call(src, "GetUrl")):find(file, 1, true) then table.insert(matches, src) end
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
        forEachProp(src, function(name, ptype)
            if ptype ~= "StrProperty" then return end
            local ok, v = pcall(function() return str(src[name]) end)
            if not ok then return end
            local newV, changed = toHalfRes(v)
            if changed then
                local okSet, err = pcall(function() src[name] = newV end)
                log(string.format("  %s.%s: %s -> %s %s", str(call(src, "GetFName")), name, v, newV,
                    okSet and "" or ("(FAILED: " .. tostring(err) .. ")")))
            end
        end)
        local after = str(call(src, "GetUrl"))
        if after ~= before and after:find("MoviesHalfRes", 1, true) then
            return src, after
        end
        log("Rewrite didn't change the source's URL. Its properties:")
        describe(src)
    end
    return nil
end

function checkPlayer(addr, mp)
    local url = str(call(mp, "GetUrl"))
    if url == "" then states[addr] = nil return end

    local st = states[addr]
    if st == nil or (url ~= st.url and url ~= st.halfUrl) then
        st = { url = url, first = tick, swaps = 0 }
        states[addr] = st
    end

    -- Our half-res copy is loading / playing
    if st.halfUrl ~= nil and url == st.halfUrl then
        if st.pending then
            if call(mp, "IsReady") then
                if not call(mp, "IsPlaying") then call(mp, "Play") end
                if RESYNC then
                    local target = math.floor(secondsSince(st.first) * 10000000)
                    local ok = pcall(function() mp:Seek({ Ticks = target }) end)
                    if not ok then log("Resync seek failed (harmless; video may lag the audio slightly)") end
                end
                st.pending, st.checked = false, true
                log("Half-res copy playing: " .. shortName(url))
            elseif secondsSince(st.swappedAt) > GIVE_UP_SECONDS then
                log("Half-res copy still not ready after " .. GIVE_UP_SECONDS .. "s: " .. shortName(url))
                st.pending, st.gaveUp = false, true
            end
        end
        return
    end

    -- Original file
    if st.checked or st.gaveUp then return end
    if not url:find("/Content/Movies/", 1, true) then st.checked = true return end

    local tooHigh, codec
    if isKnownBad(shortName(url)) then
        -- Seen before, or one of the game's level 5.2 cutscenes: redirect at once, without waiting for the decoder
        tooHigh, codec = true, knownBad[shortName(url)] and "remembered" or "level 5.2 cutscene"
    else
        if not call(mp, "IsReady") then
            -- never gets ready (the decoder refused it): switch after a while instead of leaving it black
            if call(mp, "HasError") then
                log(shortName(url) .. ": the player reports an error opening it - switching to the 1080p copy")
                return switchToHalf(mp, url, st, "open error")
            end
            return
        end
        local height = videoHeight(mp)
        tooHigh, codec = codecTooHigh(mp)
        if tooHigh == nil then
            if (st.codecWait or 0) < ticksFor(1) then st.codecWait = (st.codecWait or 0) + 1 return end
            tooHigh, codec = false, "codec not reported"
        end
        codec = codec .. (height and (", " .. height .. "p") or "")
        log(shortName(url) .. ": " .. codec)
        if not tooHigh then st.checked = true return end
    end
    return switchToHalf(mp, url, st, codec)
end

function switchToHalf(mp, url, st, codec)
    if st.swaps >= 2 then
        log("Game keeps reopening the original; leaving it alone: " .. shortName(url))
        st.gaveUp = true
        return
    end

    log(string.format("%s (%s) - redirecting its media source to the half-res copy", shortName(url), codec))
    st.swaps = st.swaps + 1

    local src, newUrl = redirectSources(url)
    if src == nil then
        log("Couldn't redirect the source; leaving this video alone (details above).")
        st.gaveUp = true
        return
    end

    st.halfUrl, st.pending, st.swappedAt = newUrl, true, tick
    rememberBad(shortName(url))
    -- Reopen from the (now redirected) source, so the game's own check sees a match
    call(mp, "OpenSource", src)
end

---------------------------------------------------------------------------
-- Watcher: runs only while something is being watched, then stops itself
---------------------------------------------------------------------------
local function livePlayers()
    local ok, list = pcall(FindAllOf, "MediaPlayer")
    local out = {}
    if ok and list then
        for _, mp in pairs(list) do
            local addr = addrOf(mp)
            if addr then out[addr] = mp end
        end
    end
    return out
end

-- a video the game failed to open: switch the player it was in (now without a URL, or still showing it)
local function handleFailed(live)
    local url = failedUrl
    failedUrl = nil
    log(shortName(url) .. ": failed to open - switching to the 1080p copy")
    local src, newUrl = redirectSources(url)
    if not src then return end
    for addr, mp in pairs(live) do
        local cur = str(call(mp, "GetUrl"))
        if cur == "" or cur:find(shortName(url), 1, true) then
            states[addr] = { url = url, first = tick, swaps = 1, halfUrl = newUrl, pending = true, swappedAt = tick }
            rememberBad(shortName(url))
            call(mp, "OpenSource", src)
            return
        end
    end
    log("  (no player found for it; the source is redirected, so the next try opens the 1080p copy)")
end

local function poll()
    tick = tick + 1
    local live = livePlayers()
    if failedUrl then handleFailed(live) end
    local pending = false
    for addr, mp in pairs(live) do
        local ok, err = pcall(checkPlayer, addr, mp)
        if not ok then log("Error: " .. tostring(err)) end
        local st = states[addr]
        if st and st.pending then pending = true end
    end
    for addr in pairs(states) do
        if live[addr] == nil then states[addr] = nil end -- that player is gone
    end
    return tick < watchUntil or pending
end

local function startLoop()
    if loopRunning then return end
    loopRunning = true
    LoopAsync(POLL_MS, function()
        if not loopRunning then return true end -- stop looping
        if busy then return false end
        busy = true
        ExecuteInGameThread(function()
            local ok, more = pcall(poll)
            if not ok then log("Poll error: " .. tostring(more)) end
            if not (ok and more) then
                loopRunning = false
                if VERBOSE then log("Watcher idle") end
            end
            busy = false
        end)
        return false
    end)
end

-- Something happened to a video (a player was created, a video opened): check every player for a while.
-- Videos already checked are checked again, as the game may reopen a player with a fresh source.
local function trigger(why)
    if not ENABLED then return end
    for _, st in pairs(states) do
        if not st.pending then st.checked, st.gaveUp = nil, nil end
    end
    watchUntil = tick + ticksFor(WATCH_SECONDS)
    if VERBOSE then log("Checking videos (" .. why .. ")") end
    startLoop()
end

---------------------------------------------------------------------------
-- Triggers: the hooks only note that something happened, and touch no game object
---------------------------------------------------------------------------
-- Unreal's "media opened" event, as handled by the game's video binder. Event handlers are
-- always invoked through reflection, so this fires even though the game opens videos from C++.
local OPEN_HOOKS = {
    "/Script/ProjectPBZ.PBZMediaImageAspectBinder:HandleMediaOpened",
}

-- The binder's handlers, logged once at start; a "...Failed" one (not in the November 2026 build) is hooked too.
-- (1.4.1 hooked them all, and HandleTracksChanged fires dozens of times per cutscene.)
local function binderHandlers()
    local names = {}
    pcall(function()
        local cls = StaticFindObject("/Script/ProjectPBZ.PBZMediaImageAspectBinder")
        if cls == nil or not cls:IsValid() then return end
        cls:ForEachFunction(function(f)
            local ok, n = pcall(function() return f:GetFName():ToString() end)
            if ok and n then table.insert(names, n) end
        end)
    end)
    table.sort(names)
    log("Video binder handlers: " .. (#names > 0 and table.concat(names, ", ") or "(none found)"))
    for _, n in ipairs(names) do
        if n:find("Fail") then table.insert(OPEN_HOOKS, "/Script/ProjectPBZ.PBZMediaImageAspectBinder:" .. n) end
    end
end

local function registerHooks()
    local ok_count = 0
    binderHandlers()
    for _, path in ipairs(OPEN_HOOKS) do
        local why = path:match(":(.+)$") or "media opened"
        local ok = pcall(RegisterHook, path, function(ctx, ...)
            if why:find("Fail") then
                -- the URL is a string parameter, not a game object: safe to read here
                local params = { ... }
                local okU, url = pcall(function() return str(params[1]:get()) end)
                if okU and url:find("/Movies/", 1, true) and not url:find("MoviesHalfRes", 1, true) then failedUrl = url end
            end
            trigger(why)
        end)
        if ok then ok_count = ok_count + 1 end
    end
    return ok_count
end

-- New players: check for a while (the player itself is not kept)
NotifyOnNewObject("/Script/MediaAssets.MediaPlayer", function() trigger("new player") end)

loadKnownBad()

local function countKnownBad()
    local n = 0
    for _ in pairs(knownBad) do n = n + 1 end
    return n
end

-- PBZ Mods Menu: settings saved, and the "forget remembered videos" action
MC.onChanged("CutsceneFix", function()
    applyConfig()
    log(string.format("Settings changed: %s, resync %s, detailed log %s",
        ENABLED and "on" or "OFF", RESYNC and "on" or "off", VERBOSE and "on" or "off"))
end)
MC.onAction("CutsceneFix", function(which)
    if which == "ForgetVideos" then
        local n = countKnownBad()
        knownBad = {}
        if KNOWN_BAD_PATH then
            local f = io.open(KNOWN_BAD_PATH, "w")
            if f then f:close() end
        end
        log("Forgot " .. n .. " remembered video(s); they are checked again the next time they play")
    end
end)
local hooked = registerHooks()
if hooked == 0 then
    log("WARNING: couldn't hook the game's media-opened handler; only newly created players will be checked.")
end

local n = countKnownBad()
log(string.format("Loaded 1.4.2%s. The game's %d level 5.2 cutscenes, and any other H.264 video above level %s, play their 1080p copy (%d remembered file%s, %d hook%s).",
    ENABLED and "" or " (switched OFF in its settings)", #BUILTIN_BAD, MAX_H264_LEVEL, n, n == 1 and "" or "s", hooked, hooked == 1 and "" or "s"))
