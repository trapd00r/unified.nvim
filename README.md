# unified.nvim

A Neovim plugin for displaying inline git diffs directly inside normal file buffers.

This version is focused on a simple editing workflow instead of a file browser:

- show added, changed, and removed lines inline in the current buffer
- diff live buffer contents, not just the version on disk
- compare against `HEAD` or any commit / ref
- open all files changed in a specific commit when only a commit hash is given
- preserve normal syntax highlighting as much as possible
- auto-refresh while editing

The main use case is:

- `:Unified` to diff the current file(s) against `HEAD`
- `:Unified <commit>` to diff the current file(s) against a specific commit
- `vim -c "Unified <commit>" <files...>` to open one or more files and immediately show inline diffs
- `vim -c "Unified <commit>"` to open all files changed in that commit

<img width="674" height="255" alt="unified" src="https://github.com/user-attachments/assets/be127078-08c1-4731-9f09-d3d2dd7528f1" />


## Features

* **Inline Diffs**: View git diffs directly in your buffer, without opening a diff split.
* **Current-file Workflow**: Works directly in normal editing buffers and supports multiple open buffers.
* **Commit Mode**: If you start Neovim with only a commit/ref, Unified opens the files changed in that commit.
* **Git Gutter Signs**: Gutter signs indicate added and removed hunks.
* **Syntax-friendly Rendering**: Normal syntax highlighting is preserved while diff lines get `DiffAdd` / `DiffDelete` style backgrounds.
* **Auto-refresh**: The diff view refreshes as you edit the buffer.

## Requirements

-   Neovim >= 0.5.0
-   Git

## Installation

You can install `unified.nvim` using your favorite plugin manager.

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'axkirillov/unified.nvim',
  opts = {
    -- your configuration comes here
  }
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'axkirillov/unified.nvim',
  config = function()
    require('unified').setup({
      -- your configuration comes here
    })
  end
}
```

## Configuration

You can configure `unified.nvim` by passing a table to the `setup()` function. Here are the default settings:

```lua
require('unified').setup({
  signs = {
    add = "│",
    delete = "│",
    change = "│",
  },
  highlights = {
    add = "DiffAdd",
    delete = "DiffDelete",
    change = "DiffChange",
  },
  line_symbols = {
    add = "+",
    delete = "-",
    change = "~",
  },
  auto_refresh = true, -- Whether to automatically refresh diff when buffer changes
  file_tree = {
    width = 0.5, -- Width of the file tree window
    filename_first = true, -- Show filename before directory path (Snacks backend only)
  },
})
```

## Usage

### Basic Commands

1.  Open a file in a git repository.
2.  Make some changes to the file.
3.  Run `:Unified` to display the diff against `HEAD`.
4.  To close the diff view, run `:Unified reset`.
5.  To show the diff against a specific commit, run `:Unified <commit_ref>`, for example `:Unified HEAD~1`.
6.  If no file buffers are open and you run `:Unified <commit_ref>`, Unified opens the files changed in that commit.

Examples:

```vim
:Unified
:Unified HEAD~1
```

From the shell:

```sh
vim -c "Unified HEAD~1" path/to/file.php
vim -c "Unified 53bff637"
```

### Example Shell Helper

If you often want "open these files with Unified enabled, or if no files are given open the files changed in this commit", a small shell function is convenient:

```sh
gD () {
	local commit="HEAD" 
	local -a files
	for arg in "$@"
	do
		if [[ -f "$arg" || -d "$arg" ]]
		then
			files+=("$arg") 
		else
			commit="$arg" 
		fi
	done
	if (( ${#files[@]} > 0 ))
	then
		vim -c "Unified $commit" "${files[@]}"
	else
		vim -c "Unified $commit"
	fi
}
```

What it does:

- treats non-file arguments as the git commit/ref to diff against
- treats file or directory arguments as paths to open in Vim
- defaults to `HEAD` if you do not pass a commit
- runs `vim -c "Unified $commit"` with the files you passed
- if you pass only a commit, opens Vim and lets Unified load all files changed in that commit

Examples:

```sh
gD
gD HEAD~1 path/to/file.php
gD 53bff637
```

### Navigating Hunks

While Unified is active, it can install buffer-local hunk navigation mappings for the diffed buffers. In the setup used here, `,n` is overridden buffer-locally to jump to the next Unified hunk without affecting your normal global mapping outside Unified buffers.

### Toggle API

For programmatic control, you can use the toggle function:

```lua
vim.keymap.set('n', '<leader>ud', require('unified').toggle, { desc = 'Toggle unified diff' })
```

This toggles the diff view on/off, remembering the previous commit reference.

### Hunk actions (API)

Unified provides a function-only API for hunk actions. Define your own keymaps or commands if desired.

Example keymaps:

```lua
local actions = require('unified.hunk_actions')
vim.keymap.set('n', 'gs', actions.stage_hunk,   { desc = 'Unified: Stage hunk' })
vim.keymap.set('n', 'gu', actions.unstage_hunk, { desc = 'Unified: Unstage hunk' })
vim.keymap.set('n', 'gr', actions.revert_hunk,  { desc = 'Unified: Revert hunk' })
```

Behavior notes:
- Operates on the hunk under the cursor inside a regular file buffer (not in the unified file tree buffer).
- Stage: applies a minimal single-hunk patch to the index.
- Unstage: reverse-applies the hunk patch from the index.
- Revert: reverse-applies the hunk patch to the working tree.
- Binary patches are skipped with a user message.
- After an action, the inline diff and file tree are refreshed automatically.

## Commands

  * `:Unified`: Shows the diff against `HEAD` using the default file tree.
  * `:Unified <commit_ref>`: Shows the diff against the specified commit reference (e.g., a commit hash, branch name, or tag) using the default file tree.
  * `:Unified -s <commit_ref>`: Shows the diff against the specified commit reference using the Snacks git_diff picker (requires snacks.nvim).
  * `:Unified reset`: Removes all unified diff highlights and signs from the current buffer and closes the file tree window if it is open.

## Development

### Running Tests

To run all automated tests:

```bash
make tests
```

To run a specific test function:

```bash
make test TEST=test_file_name.test_function_name
```

## License

MIT
