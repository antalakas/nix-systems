# Neovim Study Guide

A progressive guide to learning your nixvim-based Neovim setup. Work through each level before moving to the next.

## Level 0: Survival (Day 1)

Open a file:

    nvim myfile.py

The absolute basics you need to not get stuck:

| Key | Mode | What it does |
|-----|------|-------------|
| `i` | Normal | Enter **Insert** mode (start typing) |
| `Esc` | Insert | Return to **Normal** mode |
| `:w` | Normal | Save file |
| `:q` | Normal | Quit (fails if unsaved changes) |
| `:wq` | Normal | Save and quit |
| `:q!` | Normal | Quit without saving |
| `u` | Normal | Undo |
| `Ctrl+r` | Normal | Redo |

**The golden rule:** If you're lost, press `Esc` repeatedly to get back to Normal mode.

Neovim has **modes**. You're usually in one of these:
- **Normal** -- navigate and run commands (default when you open nvim)
- **Insert** -- type text (enter with `i`, `a`, `o`, etc.)
- **Visual** -- select text (enter with `v`, `V`, or `Ctrl+v`)
- **Command** -- run commands (enter with `:`)

## Level 1: Basic Movement (Days 2-3)

Stop using arrow keys. These are faster:

| Key | What it does |
|-----|-------------|
| `h` `j` `k` `l` | Left, Down, Up, Right |
| `w` | Jump forward one **word** |
| `b` | Jump backward one **word** |
| `0` | Jump to start of line |
| `$` | Jump to end of line |
| `gg` | Jump to top of file |
| `G` | Jump to bottom of file |
| `Ctrl+d` | Scroll half-page down |
| `Ctrl+u` | Scroll half-page up |
| `{` | Jump to previous blank line (paragraph up) |
| `}` | Jump to next blank line (paragraph down) |
| `42G` or `:42` | Go to line 42 |

**Practice:** Open a large file and navigate around using only these keys.

## Level 2: Editing (Days 3-5)

Vim edits use a **verb + noun** grammar:

**Verbs (operators):**

| Key | Verb |
|-----|------|
| `d` | **Delete** (and yank) |
| `c` | **Change** (delete and enter Insert mode) |
| `y` | **Yank** (copy) |

**Nouns (motions/text objects):**

| Key | Noun |
|-----|------|
| `w` | word (from cursor forward) |
| `iw` | inner word |
| `aw` | a word (including surrounding space) |
| `i"` | inside double quotes |
| `a"` | around double quotes (includes the quotes) |
| `i(` | inside parentheses |
| `i{` | inside curly braces |
| `it` | inside HTML/XML tag |
| `ip` | inner paragraph |

**Combine them:**

| Command | What it does |
|---------|-------------|
| `dw` | Delete word forward |
| `diw` | Delete inner word |
| `ci"` | Change inside quotes (deletes content, enters Insert) |
| `da(` | Delete around parentheses (including the parens) |
| `yip` | Yank inner paragraph |
| `dd` | Delete entire line |
| `yy` | Yank entire line |
| `cc` | Change entire line |
| `p` | Paste after cursor |
| `P` | Paste before cursor |

**Repeat:** `.` repeats the last edit. This is incredibly powerful.

## Level 3: Search and Replace (Days 5-7)

| Command | What it does |
|---------|-------------|
| `/pattern` | Search forward |
| `?pattern` | Search backward |
| `n` | Next match |
| `N` | Previous match |
| `*` | Search for word under cursor |
| `:%s/old/new/g` | Replace all occurrences in file |
| `:%s/old/new/gc` | Replace with confirmation |

Your config has `ignorecase` and `smartcase` enabled, so:
- `/hello` matches "Hello", "HELLO", "hello"
- `/Hello` matches only "Hello" (because you used a capital)

## Level 4: Your Plugins -- Navigation (Week 2)

Your leader key is **Space**. Press Space and wait -- **which-key** will show available options.

### Telescope (fuzzy finder)

| Keybinding | What it does |
|------------|-------------|
| `Space f f` | Find files by name |
| `Space f g` | Search file contents (live grep) |
| `Space f b` | Switch between open buffers |
| `Space f h` | Search help docs |

Inside Telescope:
- Type to filter results
- `Ctrl+j` / `Ctrl+k` to move up/down in results
- `Enter` to open selected file
- `Esc` to close

### Neo-tree (file explorer)

| Keybinding | What it does |
|------------|-------------|
| `Space e` | Toggle file tree sidebar |

Inside Neo-tree:
- `Enter` to open file/expand directory
- `a` to create new file
- `d` to delete
- `r` to rename
- `c` to copy
- `m` to move
- `q` to close

### Buffers and Windows

| Command | What it does |
|---------|-------------|
| `:e filename` | Open a file |
| `Space f b` | List open buffers (via Telescope) |
| `:bd` | Close current buffer |
| `Ctrl+w s` | Split window horizontally |
| `Ctrl+w v` | Split window vertically |
| `Ctrl+w h/j/k/l` | Move between splits |
| `Ctrl+w q` | Close current split |

## Level 5: Your Plugins -- Code Intelligence (Week 2-3)

### LSP (Language Server Protocol)

These work for Go, Python, Rust, and C++ out of the box:

| Keybinding | What it does |
|------------|-------------|
| `gd` | **Go to definition** |
| `gD` | Go to declaration |
| `gr` | Find all references |
| `gi` | Go to implementation |
| `K` | Hover documentation (press K on a symbol) |
| `Space c a` | Code actions (fix suggestions) |
| `Space r n` | Rename symbol across project |
| `Space d l` | Show diagnostic (error/warning) details |
| `[d` | Jump to previous diagnostic |
| `]d` | Jump to next diagnostic |

### Autocomplete (blink-cmp)

Completion pops up as you type. Uses "super-tab" preset:

| Key | What it does |
|-----|-------------|
| `Tab` | Accept completion / jump to next snippet field |
| `Shift+Tab` | Previous snippet field |
| `Ctrl+Space` | Manually trigger completion |
| `Ctrl+e` | Dismiss completion menu |

### Formatting

Your config auto-formats on save. Language formatters:
- **Go:** gofmt
- **Python:** ruff
- **Rust:** rustfmt
- **C/C++:** clang-format
- **Nix:** nixfmt

### Git (gitsigns)

| Keybinding | What it does |
|------------|-------------|
| `]c` | Next changed hunk |
| `[c` | Previous changed hunk |

The gutter shows `+` (added), `~` (modified), `-` (deleted) lines.

## Level 6: Claude Code Integration (Week 3)

### Claude Code Plugin (WebSocket IDE integration)

| Keybinding | What it does |
|------------|-------------|
| `Space a c` | Toggle Claude Code panel |
| `Space a f` | Focus Claude Code panel |
| `Space a s` | Send selected text to Claude (Visual mode) |

### Claude Terminal

| Keybinding | What it does |
|------------|-------------|
| `Space a t` | Toggle Claude in a terminal split |
| `Ctrl+\` | Toggle general terminal |

In terminal mode, press `Ctrl+\ Ctrl+n` to get back to Normal mode (to navigate away from the terminal).

### Workflow

1. Open your project: `nvim .`
2. `Space e` to browse files, `Space f f` to find by name
3. Edit code, LSP provides completions and diagnostics
4. `Space a c` to open Claude for help
5. Select code with `v`, then `Space a s` to send it to Claude
6. Files auto-format on save

## Level 7: Intermediate Skills (Month 2+)

### Macros (record and replay)

| Command | What it does |
|---------|-------------|
| `qa` | Start recording macro into register `a` |
| `q` | Stop recording |
| `@a` | Play macro `a` |
| `10@a` | Play macro `a` ten times |

### Marks

| Command | What it does |
|---------|-------------|
| `ma` | Set mark `a` at cursor position |
| `'a` | Jump to mark `a` |

### Visual Modes

| Key | What it does |
|-----|-------------|
| `v` | Character-wise visual selection |
| `V` | Line-wise visual selection |
| `Ctrl+v` | Block (column) visual selection |

In visual mode: select text, then apply an operator (`d`, `y`, `c`, `>`, `<`).

### Registers

| Command | What it does |
|---------|-------------|
| `"ay` | Yank into register `a` |
| `"ap` | Paste from register `a` |
| `"+y` | Yank to system clipboard (already default in your config) |
| `:reg` | View all registers |

## Quick Reference Card

```
MOVEMENT          EDITING           SEARCH
h j k l  arrows   i    insert       /pat  search fwd
w b      words     a    append       ?pat  search back
0 $      line      o    open below   n N   next/prev
gg G     file      dd   delete line  *     word search
Ctrl+d/u scroll    yy   yank line
{ }      paragraph cc   change line  LEADER (Space)
                   p    paste        ff  find files
SPLITS             u    undo         fg  live grep
Ctrl+w s  horiz    .    repeat       fb  buffers
Ctrl+w v  vert     Ctrl+r redo      e   file tree
Ctrl+w hjkl move                    ca  code action
                   LSP              rn  rename
EXIT               gd  definition   ac  Claude toggle
:w   save          gr  references   at  Claude term
:q   quit          K   hover docs   as  send to Claude
:wq  save+quit     [d  prev error
:q!  force quit    ]d  next error
```

## Practice Plan

**Week 1:** Levels 0-3. Open real files you work with. Force yourself not to use arrow keys or the mouse.

**Week 2:** Levels 4-5. Use `Space f f` and `Space f g` instead of the file tree when possible. Let LSP guide you through unfamiliar code with `gd` and `gr`.

**Week 3:** Level 6. Start using Claude integration for code review and generation within Neovim.

**Ongoing:** Level 7. Pick up macros, visual block mode, and registers as you encounter repetitive editing tasks.

**Tip:** Run `vimtutor` in your terminal for an interactive 30-minute tutorial that covers the fundamentals.
