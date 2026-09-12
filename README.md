# MenuPeek

MenuPocket is a macOS menu bar app.

## Run from Terminal

From this project directory:

```bash
./run.sh
```

The command builds the Debug app, restarts this checkout's running copy if needed,
and launches it. Look for the grid icon in the menu bar; the app has no Dock icon.
Build output is cached in `build/DerivedData`, so subsequent runs are incremental.
You can also invoke the script by its full path from any directory.

Requires macOS 14 or later and Xcode installed with its command-line tools selected.
Xcode does not need to be open, and no paid Apple Developer account is required.
If Terminal reports that Xcode is not selected, run this once:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```
