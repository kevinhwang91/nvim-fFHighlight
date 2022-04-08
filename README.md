# nvim-fFhighlight

Highlight the chars and words searched by `f` and `F`.

<https://user-images.githubusercontent.com/17562139/162464186-7687697e-7d88-4b50-8cc4-7400eb62e72e.mp4>

---

## Features

-   Highlight the chars searched by `f` and `F`
-   Highlight the words including the searched chars

## Quickstart

### Requirements

-   [Neovim](https://github.com/neovim/neovim) 0.5 or later

> 0.6 or later must be required for Windows users

### Installation

Install nvim-hlslens with [Packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {'kevinhwang91/nvim-fFhighlight'}
```

### Minimal configuration

```lua
require('fFhighlight').setup()
```

### Usage

After using [Minimal configuration](#Minimal-configuration):

The built-in `f` and `F` have been improved, enjoy!

## Documentation

### Setup and description

```lua
{
    disable_keymap = {
        description = [[Disable keymap,  users should map them manually]],
        default = false
    },
    disable_words_hl = {
        description = [[Disable the feature of highlighting words]],
        default = false
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
hi default fFHintChar ctermfg=yellow cterm=bold,underline guifg=yellow gui=bold,underline
hi default fFHintWords cterm=underline gui=underline
hi default fFPromptSign ctermfg=yellow cterm=bold guifg=yellow gui=bold
```

1. fFHintChar: highlight the chars
2. fFHintWords: highlight the words
3. fFPromptSign: highlight the prompt sign before searching a char

## Customize configuration

```lua
use {
    'kevinhwang91/nvim-fFHighlight',
    config = function()
        require('fFHighlight').setup({
            disable_words_hl = false,
            prompt_sign_define = {text = '✹'}
        })
    end,
    keys = {{'n', 'f'}, {'x', 'f'}, {'n', 'F'}, {'x', 'F'}}
}
```
