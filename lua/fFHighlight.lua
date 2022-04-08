local M = {}

local cmd = vim.cmd
local api = vim.api
local fn = vim.fn

local ns
local ffi

local initialized
local signGroup
local signPriority
local wordRegex
local hlPriority
local disableWordsHl
local disablePromptSign

local Context = {}
function Context:build(lnum, colsIndex, bufnr, winid)
    self.lnum = lnum
    self.colsIndex = colsIndex
    self.bufnr = bufnr or api.nvim_get_current_buf()
    self.winid = winid or api.nvim_get_current_win()
end

function Context:valid()
    local indexValid = type(self.lnum) == 'number' and type(self.colsIndex) == 'table'
    local bufValid = self.bufnr > 0 and api.nvim_buf_is_valid(self.bufnr)
    local winValid = self.winid > 0 and api.nvim_win_is_valid(self.winid)
    return indexValid and winValid and bufValid
end

function M.binarySearch(items, element, comp)
    vim.validate({items = {items, 'table'}, comp = {comp, 'function', true}})
    if not comp then
        comp = function(a, b)
            return a - b
        end
    end
    local min, max = 1, #items
    while min <= max do
        local mid = math.floor((min + max) / 2)
        local r = comp(items[mid], element)
        if r == 0 then
            return mid
        elseif r > 0 then
            max = mid - 1
        else
            min = mid + 1
        end
    end
    return -min
end

local function getCharIndexInLine(line, char)
    local index = {}
    local s
    local e = 0
    while true do
        s, e = line:find(char, e + 1, true)
        if not s then
            break
        end
        table.insert(index, s)
    end
    return index
end

local function findWordsInLineWithIndex(line, colsIndex)
    local words = {}
    local lastIndex = 1
    local lastOff = 1
    local col = colsIndex[lastIndex]
    while col and #line > 0 do
        -- s is inclusive and e is exclusive
        local s, e = wordRegex:match_str(line)
        if not s then
            break
        end
        local startCol, endCol = s + lastOff, e + lastOff - 1
        if col >= startCol and col <= endCol then
            table.insert(words, {startCol, endCol})
            while col and col <= endCol do
                lastIndex = lastIndex + 1
                col = colsIndex[lastIndex]
            end
        end
        lastOff = lastOff + e
        line = line:sub(e + 1)
    end
    return words
end

local function getKeystroke()
    ---@diagnostic disable-next-line: undefined-field
    local nr = ffi.C.get_keystroke(nil)
    return nr > 0 and nr < 128 and ('%c'):format(nr) or ''
end

local function clearVirtText(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

local function validPrefix(prefix)
    return type(prefix) == 'string' and prefix:lower() == 'f'
end

local function validMode(mode)
    if mode == 'n' or mode:lower():sub(1, 1) == 'v' or mode:byte(1, 1) == 22 then
        return true
    end
    return false
end

function M.findWith(prefix)
    assert(validPrefix(prefix), [[Only support 'f' or 'F' as a prefix]])
    local cnt = vim.v.count
    cnt = cnt == 0 and '' or tostring(cnt)

    local mode = api.nvim_get_mode().mode
    assert(validMode(mode), 'Only support normal or visual mode')

    local bufnr = api.nvim_get_current_buf()
    local lnum = api.nvim_win_get_cursor(0)[1]
    local signId
    if not disablePromptSign and vim.wo.signcolumn ~= 'no' then
        signId = fn.sign_place(0, signGroup, 'PromptSign', bufnr,
            {lnum = lnum, priority = signPriority})
        cmd('redraw')
    end
    local char = getKeystroke()
    if signId then
        fn.sign_unplace(signGroup, {buffer = bufnr, id = signId})
    end
    if #char == 0 then
        return
    end
    local curLine = api.nvim_get_current_line()
    local colsIndex = getCharIndexInLine(curLine, char)
    Context:build(lnum, colsIndex, bufnr)

    local function addVirtTextOverlap(row, startCol, endCol, hlGroup, priority)
        api.nvim_buf_set_extmark(bufnr, ns, row, startCol - 1, {
            virt_text = {{curLine:sub(startCol, endCol), hlGroup}},
            virt_text_pos = 'overlay',
            hl_mode = 'combine',
            priority = priority
        })
    end

    clearVirtText(bufnr)
    for _, i in ipairs(colsIndex) do
        addVirtTextOverlap(lnum - 1, i, i, 'fFHintChar', hlPriority + 1)
    end

    if not disableWordsHl then
        local words = findWordsInLineWithIndex(curLine, colsIndex)
        for _, word in ipairs(words) do
            local startCol, endCol = unpack(word)
            addVirtTextOverlap(lnum - 1, startCol, endCol, 'fFHintWords', hlPriority)
        end
    end

    cmd([[
        augroup fFHighlight
            au!
            au CursorMoved * lua require('fFHighlight').mayReset()
            au InsertEnter,TextChanged * lua require('fFHighlight').reset()
        augroup END
    ]])
    api.nvim_feedkeys(cnt .. prefix .. char, 'in', false)
end

function M.mayReset()
    if not Context:valid() then
        M.reset()
        return
    end

    local winid = api.nvim_get_current_win()
    if winid == Context.winid then
        local pos = api.nvim_win_get_cursor(winid)
        local lnum, col = unpack(pos)
        if lnum == Context.lnum then
            col = col + 1
            local nextColIdx = M.binarySearch(Context.colsIndex, col)
            if nextColIdx < 0 then
                M.reset()
            end
        else
            M.reset()
        end
    else
        M.reset()
    end
end

function M.reset()
    clearVirtText(Context.bufnr)
    cmd('au! fFHighlight')
end

local function initialize(config)
    local ok
    ok, ffi = pcall(require, 'ffi')
    assert(ok, 'Need a ffi module')

    ffi.cdef([[
        int get_keystroke(void *dummy_ptr);
    ]])
    ns = api.nvim_create_namespace('fF-highlight')

    if not config.disable_keymap then
        local kopt = {noremap = true, silent = true}
        api.nvim_set_keymap('n', 'f', [[<Cmd>lua require('fFHighlight').findWith('f')<CR>]], kopt)
        api.nvim_set_keymap('x', 'f', [[<Cmd>lua require('fFHighlight').findWith('f')<CR>]], kopt)
        api.nvim_set_keymap('n', 'F', [[<Cmd>lua require('fFHighlight').findWith('F')<CR>]], kopt)
        api.nvim_set_keymap('x', 'F', [[<Cmd>lua require('fFHighlight').findWith('F')<CR>]], kopt)
    end
    disableWordsHl = config.disable_words_hl

    cmd([[
        hi default fFHintChar ctermfg=yellow cterm=bold,underline guifg=yellow gui=bold,underline
        hi default fFHintWords cterm=underline gui=underline
        hi default fFPromptSign ctermfg=yellow cterm=bold guifg=yellow gui=bold
    ]])

    wordRegex = vim.regex([[\k\+]])
    hlPriority = 4096
    signPriority = 90
    signGroup = 'fFSignGroup'
    if type(config.prompt_sign_define) ~= 'table' then
        disablePromptSign = true
    else
        disablePromptSign = false
        fn.sign_define('PromptSign', config.prompt_sign_define)
    end
end

function M.setup(opts)
    local config = vim.tbl_deep_extend('keep', opts or {},
        {disable_keymap = false, disable_words_hl = false})

    if config.prompt_sign_define and vim.tbl_isempty(config.prompt_sign_define) then
        config.prompt_sign_define = nil
    else
        config.prompt_sign_define = vim.tbl_deep_extend('keep', config.prompt_sign_define or {}, {
            text = '->',
            text_hl = 'fFPromptSign',
            culhl = 'fFPromptSign'
        })
    end
    vim.validate({
        disable_keymap = {config.disable_keymap, 'boolean'},
        disable_words_hl = {config.disable_words_hl, 'boolean'},
        prompt_sign_define = {config.prompt_sign_define, 'table', true}
    })

    if not initialized then
        initialize(config)
        initialized = true
    end
end

return M
