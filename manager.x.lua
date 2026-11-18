-- ycode-manager: list every Lua mod in the hooks directory and enable/disable them.
--
-- A status bar button (and "manager: open" in the command palette) opens the manager.
-- Mods are the hook files (`*.lua`, `*.x.lua`) and extension directories in ycode's
-- hooks directory (`ycode.hooks_dir`). Disabling moves one into hooks/.disabled/ (the loader skips
-- dot-directories); enabling moves it back. Changes apply with a hook reload.

local HOOKS = ycode.hooks_dir
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
    local detail = mod.desc ~= "" and mod.desc or (mod.target and ("→ " .. mod.target))
        or (mod.dir and "extension" or "file")
    local toggle
    if mod.name == SELF then
        toggle = { "text", "this manager", size = "small", color = "muted" }
    else
        toggle = { "checkbox", id = "toggle-" .. mod.name, checked = mod.enabled,
            on_click = function(w)
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
    return { "list_item", mod.name, id = "mod-" .. mod.name, detail = detail,
        color = mod.enabled and "default" or "muted",
        tooltip = mod.target or mod.path,
        start = { "icon", name = mod.dir and "folder" or "file_code",
                  color = mod.enabled and "default" or "muted" },
        end_ = toggle }
end

local function render(w)
    local st = w.state
    st.mods = st.mods or scan()
    local enabled = 0
    for _, m in ipairs(st.mods) do if m.enabled then enabled = enabled + 1 end end
    local mods = { "section", HOOKS, empty = "no mods" }
    for _, m in ipairs(st.mods) do mods[#mods + 1] = row(w, m) end
    return { "panel", id = "mods",
        header = { title = "Mods", context = enabled .. "/" .. #st.mods .. " enabled", actions = {
            { "icon_button", icon = "rotate_ccw", tooltip = "Rescan mods",
              on_click = function(w) st.mods = scan() end },
            { "button", st.dirty and "Reload to apply" or "Reload hooks",
              style = st.dirty and "filled" or "subtle",
              tooltip = "Reload hooks so enable/disable changes take effect",
              on_click = function(w) apply() end } } },
        footer = st.message, color = st.dirty and "warning" or nil,
        mods }
end

local function open()
    gpui.open_window{
        title = "ycode mods", width = 620, height = 520,
        state = {},
        render = function(w)
            local ok, tree = pcall(render, w)
            if ok then return tree end
            return { "empty", "ycode-manager: " .. tostring(tree), color = "error" }
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
