# nvim-fFHighlight

Highlight the chars and words searched by `f` and `F`.

<https://user-images.githubusercontent.com/17562139/162574749-b205e13f-8fe4-418f-a68f-56183cb421f7.mp4>

---

## Table of contents

* [Table of contents](#table-of-contents)
* [Features](#features)
* [Quickstart](#quickstart)
  * [Requirements](#requirements)
  * [Installation](#installation)
  * [Minimal configuration](#minimal-configuration)
  * [Usage](#usage)
* [Documentation](#documentation)
  * [Setup and description](#setup-and-description)
  * [Highlight](#highlight)
  * [API](#api)
* [Customize configuration](#customize-configuration)
* [Feedback](#feedback)
* [License](#license)

## Features

- Highlight the chars searched by `f` and `F`
- Highlight the words including the searched chars
- Overlap the chars as numbers to jump faster

## Quickstart

### Requirements

- [Neovim](https://github.com/neovim/neovim) 0.5 or later

> 0.6 or later must be required for Windows users

### Installation

Install nvim-fFHighlight with [Packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {'kevinhwang91/nvim-fFHighlight'}
```

### Minimal configuration

```lua
require('fFHighlight').setup()
```

### Usage

After using [Minimal configuration](#Minimal-configuration):

The built-in `f` and `F` have been improved, enjoy!

## Documentation

### Setup and description

```lua
{
    disable_keymap = {
        description = [[Disable keymaps, users should map them manually]],
        default = false
    },
    disable_words_hl = {
        description = [[Disable the feature of highlighting words]],
        default = false
    },
    number_hint_threshold = {
        description = [[If the count of repeating latest `f` or `F` to the char is equal or greater
                        than this value, use number to overlap char. minimal value is 2]],
        default = 3
    },
    prompt_sign_define = {
        description = [[The optional dict argument for sign_define(), `:h sign_define()` for
                        more details. If this value is `{}`, will disable sign for prompt]],
        default = {text = '->', text_hl = 'fFPromptSign', culhl = 'fFPromptSign'}
    }
}
```

### Highlight

```vim
hi default fFHintChar ctermfg=yellow cterm=bold guifg=yellow gui=bold
hi default fFHintNumber ctermfg=yellow cterm=bold guifg=yellow gui=bold
hi default fFHintWords cterm=underline gui=underline
hi default link fFHintCurrentWord fFHintWords
hi default fFPromptSign ctermfg=yellow cterm=bold guifg=yellow gui=bold
```

1. fFHintChar: highlight the hint of chars
2. fFHintNumber: highlight the hint of number
3. fFHintWords: highlight the hint of words
4. fFHintCurrentWord: highlight the hint of current word
5. fFPromptSign: highlight the prompt sign before searching a char

### API

```lua
-- All API under this module
local m = require('fFHighlight')

--- Find the character to be typed on the current line
---@param backward? boolean the direction of finding character. true is backward, otherwise is forward
m.findChar(backward)
```

## Customize configuration

```lua
use {
    'kevinhwang91/nvim-fFHighlight',
    config = function()
        vim.cmd([[
            hi fFHintChar ctermfg=yellow cterm=bold,undercurl guifg=yellow gui=bold,undercurl
            hi fFHintWords cterm=undercurl gui=undercurl guisp=yellow
            hi fFPromptSign ctermfg=yellow cterm=bold guifg=yellow gui=bold
        ]])
        require('fFHighlight').setup({
            disable_keymap = false,
            disable_words_hl = false,
            number_hint_threshold = 3,
            prompt_sign_define = {text = '✹'}
        })
    end,
    keys = {{'n', 'f'}, {'x', 'f'}, {'n', 'F'}, {'x', 'F'}}
}
```

## Feedback

- If you get an issue or come up with an awesome idea, don't hesitate to open an issue in github.
- If you think this plugin is useful or cool, consider rewarding it a star.

## License

The project is licensed under a BSD-3-clause license. See [LICENSE](./LICENSE) file for details.
