# fcd – Terminal Directory Picker (Zig)

fcd is a small terminal-based directory picker written in Zig, using zigtui.
It lets you navigate directories with the keyboard and outputs a shell-compatible
cd command for fast directory switching.

## Features
- Navigate directories (j / k)
- Enter directory (Enter)
- Go up (Backspace)
- Toggle hidden directories (H)
- Sorts directories alphabetically
- Cross-platform (Unix / Windows)
- Lightweight and fast

## Controls

Key | Action
--- | ---
j | Move down
k | Move up
Enter | Enter directory
Backspace | Go to parent directory
H | Toggle hidden directories
O | Output cd command and quit
Q / Esc | Quit

## Usage

Run fcd, navigate to a directory, then press O.
The program writes a command to:

/tmp/fcd_move_dir

You can integrate this with your shell to automatically change directories.

## Build

zig build

## Notes
- Hidden directories are dot-prefixed on Unix
- Windows hidden attributes are not currently detected
- The app manages its own working directory (no global chdir)

