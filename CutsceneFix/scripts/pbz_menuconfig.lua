-- pbz_menuconfig.lua: shared helper for UE4SS mods that work with the PBZ Mods Menu (FOR-MOD-AUTHORS.md, section 2).
-- Settings live in <ModName>.config.json in the mod's folder: defaults first, the file's values on top, and the file is
-- created from the defaults when missing (the menu's bridge only replaces a config that already exists).
-- Load it with dofile(<mod folder> .. "/scripts/pbz_menuconfig.lua"), so each mod uses its own copy.

local M = {}

---------------------------------------------------------------------------- JSON (one flat object)
local function skip(s, i)
    return s:find("[^ \t\r\n]", i) or #s + 1
end

local function parseString(s, i)
    local out, j = {}, i + 1
    while j <= #s do
        local c = s:sub(j, j)
        if c == '"' then
            return table.concat(out), j + 1
        elseif c == "\\" then
            local e = s:sub(j + 1, j + 1)
            local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
            if map[e] then
                out[#out + 1] = map[e]; j = j + 2
            elseif e == "u" then
                local code = tonumber(s:sub(j + 2, j + 5), 16)
                if not code then return nil, "bad \\u escape" end
                out[#out + 1] = utf8 and utf8.char(code) or "?"; j = j + 6
            else
                return nil, "bad escape"
            end
        else
            out[#out + 1] = c; j = j + 1
        end
    end
    return nil, "unterminated string"
end

function M.decode(s)
    if type(s) ~= "string" then return nil, "no text" end
    s = s:gsub("^\239\187\191", "") -- UTF-8 byte order mark
    local i = skip(s, 1)
    if s:sub(i, i) ~= "{" then return nil, "not an object" end
    local t = {}
    i = skip(s, i + 1)
    if s:sub(i, i) == "}" then return t end
    while true do
        if s:sub(i, i) ~= '"' then return nil, "expected a key" end
        local k, err
        k, i = parseString(s, i)
        if not k then return nil, i end
        i = skip(s, i)
        if s:sub(i, i) ~= ":" then return nil, "expected :" end
        i = skip(s, i + 1)
        local c = s:sub(i, i)
        local v
        if c == '"' then
            v, i = parseString(s, i)
            if v == nil then return nil, i end
        elseif s:sub(i, i + 3) == "true" then
            v, i = true, i + 4
        elseif s:sub(i, i + 4) == "false" then
            v, i = false, i + 5
        elseif s:sub(i, i + 3) == "null" then
            v, i = nil, i + 4
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
            v = num and tonumber(num)
            if v == nil then return nil, "bad value for " .. k end
            i = i + #num
        end
        t[k] = v
        i = skip(s, i)
        c = s:sub(i, i)
        if c == "}" then return t end
        if c ~= "," then return nil, "expected , or }" end
        i = skip(s, i + 1)
    end
end

local function encodeValue(v)
    if type(v) == "boolean" then return v and "true" or "false" end
    if type(v) == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
        return (string.format("%.6f", v):gsub("0+$", ""):gsub("%.$", ""))
    end
    local esc = tostring(v):gsub('[%c"\\]', function(c)
        local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
        return map[c] or string.format("\\u%04x", c:byte())
    end)
    return '"' .. esc .. '"'
end

-- order: list of keys, written first and in that order; any other keys follow sorted
function M.encode(t, order)
    local keys, seen = {}, {}
    for _, k in ipairs(order or {}) do
        if t[k] ~= nil then keys[#keys + 1] = k; seen[k] = true end
    end
    local rest = {}
    for k in pairs(t) do
        if not seen[k] then rest[#rest + 1] = k end
    end
    table.sort(rest)
    for _, k in ipairs(rest) do keys[#keys + 1] = k end
    local lines = {}
    for _, k in ipairs(keys) do
        lines[#lines + 1] = "  " .. encodeValue(k) .. ": " .. encodeValue(t[k])
    end
    return "{\n" .. table.concat(lines, ",\n") .. "\n}\n"
end

---------------------------------------------------------------------------- the mod's folder and config
function M.modDir(level)
    local src = (debug.getinfo(level or 2, "S").source or ""):gsub("^@", "")
    return src:match("^(.*)[/\\][Ss]cripts[/\\][^/\\]+$")
end

-- Returns a config object: cfg.values (defaults + file), cfg:load(), cfg:save(), cfg.path
-- defaults: { key = value }, order: list of keys for writing, migrate: optional function() -> table of old values
function M.config(modName, dir, defaults, order, migrate, log)
    local cfg = { values = {}, path = dir and (dir .. "/" .. modName .. ".config.json") or nil }
    log = log or function() end

    function cfg:save()
        if not self.path then return false end
        local f = io.open(self.path, "w")
        if not f then log("could not write " .. self.path); return false end
        f:write(M.encode(self.values, order))
        f:close()
        return true
    end

    function cfg:load()
        local v = {}
        for k, d in pairs(defaults) do v[k] = d end
        local f = self.path and io.open(self.path, "r")
        local file, err
        if f then
            file, err = M.decode(f:read("a"))
            f:close()
            if not file then log(modName .. ".config.json unreadable (" .. tostring(err) .. "), using defaults") end
        end
        local fresh = (f == nil)
        if fresh and migrate then
            local ok, old = pcall(migrate)
            if ok and type(old) == "table" then
                for k, x in pairs(old) do v[k] = x end
                log("settings carried over from the old config file")
            end
        end
        for k, x in pairs(file or {}) do
            -- a value of the wrong type (hand edit) keeps the default
            if defaults[k] == nil or type(x) == type(defaults[k]) then v[k] = x end
        end
        self.values = v
        if fresh then self:save() end
        return v
    end

    return cfg
end

---------------------------------------------------------------------------- keys
-- The Mods Menu writes the engine's key names; UE4SS's Key table uses its own.
local ENGINE_TO_UE4SS = {
    PageUp = "PAGE_UP", PageDown = "PAGE_DOWN", Home = "HOME", End = "END", Insert = "INS", Delete = "DEL",
    NumPadZero = "NUM_ZERO", NumPadOne = "NUM_ONE", NumPadTwo = "NUM_TWO", NumPadThree = "NUM_THREE",
    NumPadFour = "NUM_FOUR", NumPadFive = "NUM_FIVE", NumPadSix = "NUM_SIX", NumPadSeven = "NUM_SEVEN",
    NumPadEight = "NUM_EIGHT", NumPadNine = "NUM_NINE",
    Multiply = "MULTIPLY", Add = "ADD", Subtract = "SUBTRACT", Decimal = "DECIMAL", Divide = "DIVIDE",
    Zero = "ZERO", One = "ONE", Two = "TWO", Three = "THREE", Four = "FOUR", Five = "FIVE", Six = "SIX",
    Seven = "SEVEN", Eight = "EIGHT", Nine = "NINE",
}

-- engine or UE4SS key name -> Key value, or nil (None / unknown)
function M.key(name)
    if type(name) ~= "string" or name == "" or name:lower() == "none" then return nil end
    local u = ENGINE_TO_UE4SS[name] or name:upper()
    return Key[u]
end

-- A key bound to a setting that can change while playing. UE4SS can't unbind, so each key is registered once, the first
-- time it is used, and its handler only acts while it is the current key. modifiers: {} or { ModifierKey.CONTROL }, ...
function M.keyBinding(fn, modifiers)
    local kb = { current = nil, registered = {} }
    function kb:set(name)
        local k = M.key(name)
        self.current = k
        if k and not self.registered[k] then
            self.registered[k] = true
            local mine = k
            local ok = pcall(RegisterKeyBind, mine, modifiers or {}, function()
                if kb.current == mine then fn() end
            end)
            if not ok then self.registered[k] = nil end
        end
        return k ~= nil
    end
    return kb
end

---------------------------------------------------------------------------- menu events
local function encodeName(name)
    return (name:gsub("[^%w_]", function(c) return string.format("%%%02x", c:byte()) end))
end

function M.onChanged(modName, fn)
    pcall(RegisterConsoleCommandGlobalHandler, "ModsMenuChanged_" .. encodeName(modName), function()
        fn()
        return true
    end)
end

function M.onAction(modName, fn)
    pcall(RegisterConsoleCommandGlobalHandler, "ModsMenuAction_" .. encodeName(modName), function(_, params)
        fn(params and params[1])
        return true
    end)
end

return M
