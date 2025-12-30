# fcd
`fcd` is a **minimal TUI directory picker** written in **Zig**.  
It lets you quickly browse directories and change your shell’s working directory.


## Why this exists
I was tired of cd-ing to directories :)


## Installation

### Build

```sh
zig build-exe fcd.zig -lc -lncursesw
```

Move the binary somewhere in your `$PATH`:

```sh
mv fcd ~/.local/bin/
```


## Shell setup (required)

Add this function to your shell config (`~/.bashrc`, `~/.zshrc`, etc.):

```sh
fcd() {
    command fcd "$@"
    if [ -f /tmp/zig-tui-cd ]; then
        source /tmp/zig-tui-cd
        rm -f /tmp/zig-tui-cd
    fi
}
```

Reload your shell:

```sh
source ~/.bashrc
```

> ⚠️ Running `./fcd` directly will **not** change your shell directory.  
> You must use the shell function.

## Usage

```sh
fcd
```

### Key bindings

| Key | Action |
|----|-------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `Enter` | Enter directory |
| `Ctrl + H` | Toggle hidden directories |
| `/` | Start filter |
| `Backspace` | Edit filter |
| `Enter` (in filter) | Apply filter |
| `Esc` | Cancel filter |
| `q` | Quit |


## Requirements
- ncurses (`ncursesw`)
- Zig **0.15.x**

## License
MIT 
