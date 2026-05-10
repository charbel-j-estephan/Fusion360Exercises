# Fusion 360 Exercises

42 modeling exercises in Autodesk Fusion 360.

This repo auto-syncs to GitHub: a background `auto-sync.ps1` watcher commits and pushes any change within ~5 seconds of the last save.

## Auto-sync setup

- `auto-sync.ps1` — watcher script (PowerShell `FileSystemWatcher`, 5 s debounce).
- `auto-sync-launch.vbs` — launches the watcher hidden (no console window).
- A shortcut in `shell:startup` runs the watcher on login.
- `auto-sync.log` — local log of sync activity (gitignored).

## Manual control

Stop the running watcher: end the matching `powershell.exe` process in Task Manager.

Run once on demand:

```powershell
git -C "C:\Users\Charbel\DC\Fusion\laptop\fusion 360 exercices" add -A
git -C "C:\Users\Charbel\DC\Fusion\laptop\fusion 360 exercices" commit -m "manual sync"
git -C "C:\Users\Charbel\DC\Fusion\laptop\fusion 360 exercices" push
```
