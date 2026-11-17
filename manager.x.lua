-- ycode-manager: list every Lua mod in the hooks directory and enable/disable them.
--
-- A status bar button (and "manager: open" in the command palette) opens the manager.
-- Mods are the hook files (`*.lua`, `*.x.lua`) and extension directories in
-- ~/.config/zed/hooks. Disabling moves one into hooks/.disabled/ (the loader skips
-- dot-directories); enabling moves it back. Changes apply with a hook reload.

local HOOKS = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/zed/hooks"
local DISABLED = HOOKS .. "/.disabled"
local SELF = "ycode-manager"
local REOPEN_KEY = "ycode-manager-reopen"

local function q(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function ls(dir)
    local names = {}
    local p = io.popen("ls -1A " .. q(dir) .. " 2>/dev/null")
    if not p then return names end
    for name in p:lines() do names[#names + 1] = name end
    p:close()
    table.sort(names)
    return names
end

local function is_dir(path)
    local ok = os.execute("test -d " .. q(path))
    return ok == true or ok == 0
end

local function link_target(path)
    local p = io.popen("readlink " .. q(path) .. " 2>/dev/null")
    if not p then return nil end
    local t = p:read("l")
    p:close()
    return t ~= "" and t or nil
end

-- First comment line of a hook file: "-- name: what it does" -> "what it does".
local function describe_file(path)
    local f = io.open(path)
    if not f then return nil end
    for line in f:lines() do
        local c = line:match("^%-%-%s*(.-)%s*$")
        if c and c ~= "" then
            f:close()
            return c:match("^[%w%-_.]+:%s*(.+)$") or c
        end
        if not line:match("^%s*$") then break end
    end
    f:close()
    return nil
end

local function is_hook_file(name)
    return name:match("%.lua$") ~= nil
end

local function describe(path, dir)
    if not dir then return describe_file(path) end
    for _, f in ipairs(ls(path)) do
        if is_hook_file(f) then
            local d = describe_file(path .. "/" .. f)
            if d then return d end
        end
    end
end

-- Every mod, enabled (in HOOKS) or disabled (in DISABLED).
local function scan()
    local mods = {}
    local function add(base, name, enabled)
        local path = base .. "/" .. name
        local dir = is_dir(path)
        if dir then
            if name == "lib" or name:sub(1, 1) == "." then return end
        elseif not is_hook_file(name) then
            return
        end
        mods[#mods + 1] = {
            name = name,
            path = path,
            dir = dir,
            enabled = enabled,
            target = link_target(path),
            desc = describe(path, dir) or "",
        }
    end
    for _, n in ipairs(ls(HOOKS)) do add(HOOKS, n, true) end
    for _, n in ipairs(ls(DISABLED)) do add(DISABLED, n, false) end
    table.sort(mods, function(a, b) return a.name:lower() < b.name:lower() end)
    return mods
end

local function move(mod, enable)
    local dest = (enable and HOOKS or DISABLED) .. "/" .. mod.name
    if not enable then os.execute("mkdir -p " .. q(DISABLED)) end
    local ok, err = os.rename(mod.path, dest)
    if not ok then return false, err end
    return true
end

local function apply()
    -- Reloading closes Lua windows; reopen this one once the new runtime is up.
    ycode.kv_set(REOPEN_KEY, "1")
    ycode.dispatch("ycode::ReloadHooks")
end

local function row(w, mod)
    local st = w.state
    local kind = mod.dir and "extension" or "file"
    local info = { "col", grow = true, gap = 2,
        { "row", gap = 8,
            { "text", mod.name, bold = true, fg = mod.enabled and "text" or "muted" },
            { "text", mod.enabled and "enabled" or "disabled", size = 12,
              fg = mod.enabled and "success" or "muted" },
        },
    }
    if mod.desc ~= "" then
        info[#info + 1] = { "text", mod.desc, size = 12, fg = "muted" }
    end
    info[#info + 1] = { "text", mod.target and ("→ " .. mod.target) or kind,
        size = 11, mono = true, fg = "muted" }

    local action
    if mod.name == SELF then
        action = { "text", "this manager", size = 12, fg = "muted" }
    else
        action = { "button", mod.enabled and "Disable" or "Enable", on_click = function(w)
            local ok, err = move(mod, not mod.enabled)
            if ok then
                st.dirty = true
                st.message = (mod.enabled and "disabled " or "enabled ") .. mod.name
                    .. "; reload to apply"
            else
                st.message = "could not move " .. mod.name .. ": " .. tostring(err)
            end
            st.mods = scan()
        end }
    end
    return { "row", gap = 10, p = 8, align = "center", rounded = 6, bg = "surface", info, action }
end

local function render(w)
    local st = w.state
    st.mods = st.mods or scan()
    local enabled = 0
    for _, m in ipairs(st.mods) do if m.enabled then enabled = enabled + 1 end end
    local list = { "col", id = "mods", scroll = true, grow = true, gap = 6 }
    for _, m in ipairs(st.mods) do list[#list + 1] = row(w, m) end
    if #st.mods == 0 then list[#list + 1] = { "text", "no mods in " .. HOOKS, fg = "muted" } end
    return { "col", w = "full", h = "full", p = 14, gap = 10,
        { "row", gap = 8, align = "center",
            { "text", "Mods", bold = true, size = 16, grow = true },
            { "text", enabled .. "/" .. #st.mods .. " enabled", fg = "muted" },
        },
        { "text", HOOKS, mono = true, size = 11, fg = "muted" },
        list,
        { "row", gap = 8, align = "center",
            { "text", st.message or "", size = 12, grow = true,
              fg = st.dirty and "warning" or "muted" },
            { "button", "Refresh", on_click = function(w) st.mods = scan() end },
            { "button", st.dirty and "Reload hooks to apply" or "Reload hooks",
              on_click = function(w) apply() end },
        },
    }
end

local function open()
    gpui.open_window{
        title = "ycode mods", width = 620, height = 520,
        state = {},
        render = function(w)
            local ok, tree = pcall(render, w)
            if ok then return tree end
            return { "text", "ycode-manager: " .. tostring(tree), fg = "error" }
        end,
    }
end

%ctor
    ycode.status_button{
        id = "ycode-manager", icon = "blocks", tooltip = "ycode mods",
        action = "manager::Open",
    }
    -- Only after our own "Reload hooks" (never on a normal startup).
    if ycode.kv_get(REOPEN_KEY) then
        ycode.kv_set(REOPEN_KEY, nil)
        open()
    end
end

%hook manager
%new - Open
    open()
end
%end
