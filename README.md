# ycode-manager

Mod manager for [ycode](https://github.com/jbisfun/ycode)'s Lua hooks. A button in the
status bar (blocks icon), or "manager: open" in the command palette, opens a window that
lists every mod in `~/.config/zed/hooks`, with its description (the first comment line of
its hook file), where it links to, and whether it is enabled.

Disable moves a mod into `hooks/.disabled/` (the loader skips dot-directories); Enable
moves it back. "Reload hooks" applies the changes and reopens the manager.

## Install

    ln -s ~/jbisfun/ycode-manager ~/.config/zed/hooks/ycode-manager

then "ycode: reload hooks". Needs ycode with `ycode.status_button`.
