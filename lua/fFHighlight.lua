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
local has09
local disableWordsHl
local disablePromptSign
local numberHintThreshold

local function setVirtTextOverlap(bufnr, row, col, char, hlName, opts)
    opts = opts or {}
    -- may throw error: value outside range while editing
    local ok, res = pcall(api.nvim_buf_set_extmark, bufnr, ns, row, col, {
        id = opts.id,
        virt_text = {{char, hlName}},
        virt_text_pos = 'overlay',
        hl_mode = 'combine',
        priority = opts.priority
    })
    return ok and res or nil
end

local function getHighestVirtTextPriorityInLine(bufnr, row)
    local marks
    if has09 then
        marks = api.nvim_buf_get_extmarks(bufnr, -1, {row, 0}, {row + 1, 0}, {details = true})
    else
        marks = {}
        for _, n in pairs(api.nvim_get_namespaces()) do
            if n ~= ns then
                for _, m in ipairs(api.nvim_buf_get_extmarks(bufnr, n, {row, 0}, {row + 1, 0}, {details = true})) do
                    table.insert(marks, m)
                end
            end
        end
    end
    local max = 2048
    for _, m in ipairs(marks) do
        local details = m[4]
        if details.virt_text and max < details.priority then
            max = details.priority
        end
    end
    return max
end

local function clearVirtText(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

---@class Context
---@field char string
---@field lnum number
---@field cols number[]
---@field virtTextIds? number[]
---@field wordRanges? table<number, number[]>
---@field curWordVirtTextId? number
---@field bufnr number
---@field winid number
---@field hlPriority number
local Context = {}
function Context:build(char, lnum, cols, wordRanges, bufnr, winid, hlPriority)
    self.char = char
    self.lnum = lnum
    self.cols = cols
    self.virtTextIds = nil
    self.wordRanges = wordRanges
    self.curWordVirtTextId = nil
    self.bufnr = bufnr
    self.winid = winid
    self.hlPriority = hlPriority
end

function Context:valid()
    local charValid = type(self.char) == 'string' and #self.char == 1
    local indexValid = type(self.lnum) == 'number' and type(self.cols) == 'table'
    local winValid = self.winid and self.winid > 0 and api.nvim_win_is_valid(self.winid)
    return charValid and indexValid and winValid
end

function Context:refreshHint(backwardColIdx, forwardColIdx)
    local bufnr, lnum, cols, char = self.bufnr, self.lnum, self.cols, self.char
    local changedIds = {}
    local priority = self.hlPriority
    if not self.virtTextIds then
        local virtTextIds = {}
        for _, col in ipairs(cols) do
            local id = setVirtTextOverlap(bufnr, lnum - 1, col - 1, char, 'fFHintChar',
                {priority = priority})
            if id then
                table.insert(virtTextIds, id)
                changedIds[id] = true
            end
        end
        self.virtTextIds = virtTextIds
    end

    for i = math.min(backwardColIdx - numberHintThreshold, #cols), 1, -1 do
        local id = self.virtTextIds[i]
        local col = cols[i]
        local num = backwardColIdx - i
        if num > 9 then
            break
        end
        setVirtTextOverlap(bufnr, lnum - 1, col - 1, tostring(num), 'fFHintNumber',
            {id = id, priority = priority})
        changedIds[id] = true
    end
    for i = forwardColIdx + numberHintThreshold, #cols do
        local id = self.virtTextIds[i]
        local col = cols[i]
        local num = i - forwardColIdx
        if num > 9 then
            break
        end
        setVirtTextOverlap(bufnr, lnum - 1, col - 1, tostring(num), 'fFHintNumber',
            {id = id, priority = priority})
        changedIds[id] = true
    end
    for i, id in ipairs(self.virtTextIds) do
        if not changedIds[id] then
            local col = cols[i]
            setVirtTextOverlap(bufnr, lnum - 1, col - 1, char, 'fFHintChar',
                {id = id, priority = priority})
        end
    end
end

function Context:refreshCurrentWord(curColIdx)
    if not self.wordRanges then
        return
    end
    local bufnr, lnum = self.bufnr, self.lnum
    local curCol = self.cols[curColIdx]
    local startCol, endCol
    for _, range in ipairs(self.wordRanges) do
        local s, e = unpack(range)
        if s <= curCol and curCol <= e then
            startCol, endCol = s, e
            break
        end
    end

    if startCol and endCol then
        local curLine = api.nvim_get_current_line()
        if not self.curWordVirtTextId then
            Context.curWordVirtTextId = setVirtTextOverlap(bufnr, lnum - 1, startCol - 1,
                curLine:sub(startCol, endCol), 'fFHintCurrentWord', {priority = self.hlPriority - 1})
        else
            setVirtTextOverlap(bufnr, lnum - 1, startCol - 1, curLine:sub(startCol, endCol),
                'fFHintCurrentWord', {id = self.curWordVirtTextId, priority = self.hlPriority - 1})
        end
    end
end

local function binarySearch(items, element, comp)
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

local function findCharColsInLine(line, char, col)
    local cols = {}
    local i = 0
    local s
    local e = 0
    while true do
        s, e = line:find(char, e + 1, true)
        if not s then
            break
        end
        table.insert(cols, s)
        if s == col then
            i = #cols
        elseif s < col then
            i = - #cols
        end
    end
    return cols, i
end

local function findWordRangesInLineWithCols(line, cols)
    local ranges = {}
    local lastIdx = 1
    local lastOff = 1
    local col = cols[lastIdx]
    while col and #line > 0 do
        -- s is inclusive and e is exclusive
        local s, e = wordRegex:match_str(line)
        if not s then
            break
        end
        local startCol, endCol = s + lastOff, e + lastOff - 1
        if col >= startCol and col <= endCol then
            table.insert(ranges, {startCol, endCol})
            while col and col <= endCol do
                lastIdx = lastIdx + 1
                col = cols[lastIdx]
            end
        end
        lastOff = lastOff + e
        line = line:sub(e + 1)
    end
    return ranges
end

local function getKeystroke()
    ---@diagnostic disable-next-line: undefined-field
    local nr = ffi and ffi.C.get_keystroke(nil) or fn.getchar()
    -- C-c throw E5108: Error executing lua Keyboard interrupt
    -- `got_int` have been set to true, need an extra pcall command to eat it
    if ffi and nr == 3 then
        pcall(vim.cmd, '')
    end
    return nr > 0 and nr < 128 and ('%c'):format(nr) or ''
end

local function isFloatWin(winid)
    return fn.win_gettype(winid) == 'popup'
end

local function validMode(mode)
    if mode == 'n' or mode == 'nt' or mode:lower():sub(1, 1) == 'v' or mode:byte(1, 1) == 22 then
        return true
    end
    return false
end

--- Find the character to be typed on the current line
---@param backward? boolean the direction of finding character. true is backward, otherwise is forward
function M.findChar(backward)
    assert(initialized, [[Not initialized yet, `require('fFHighlight').setup()` is required]])
    local mode = api.nvim_get_mode().mode
    assert(validMode(mode), 'Only support normal or visual mode')

    local bufnr = api.nvim_get_current_buf()
    local winid = api.nvim_get_current_win()
    local lnum, curCol = unpack(api.nvim_win_get_cursor(0))
    curCol = curCol + 1
    local signId
    if not disablePromptSign then
        if not (vim.wo.signcolumn == 'auto' and isFloatWin(winid)) then
            signId = fn.sign_place(0, signGroup, 'PromptSign', bufnr,
                {lnum = lnum, priority = signPriority})
            cmd('redraw')
        end
    end
    local char = getKeystroke()
    if signId then
        fn.sign_unplace(signGroup, {buffer = bufnr, id = signId})
    end
    if #char == 0 then
        return
    end
    local curLine = api.nvim_get_current_line()
    local cols, curColIdx = findCharColsInLine(curLine, char, curCol)
    clearVirtText(bufnr)
    local hlPriority = getHighestVirtTextPriorityInLine(bufnr, lnum - 1) + 3

    local wordRanges
    if not disableWordsHl then
        wordRanges = findWordRangesInLineWithCols(curLine, cols)
        for _, range in ipairs(wordRanges) do
            local startCol, endCol = unpack(range)
            setVirtTextOverlap(bufnr, lnum - 1, startCol - 1, curLine:sub(startCol, endCol),
                'fFHintWords', {priority = hlPriority - 2})
        end
    end
    Context:build(char, lnum, cols, wordRanges, bufnr, winid, hlPriority)
    cmd([[
        augroup fFHighlight
            au!
            au CursorMoved * lua require('fFHighlight').move()
            au InsertEnter,TextChanged * lua require('fFHighlight').dispose()
        augroup END
    ]])
    local nextColIdx
    local cnt = vim.v.count1
    if backward then
        nextColIdx = curColIdx <= 0 and -curColIdx or curColIdx - cnt
    else
        nextColIdx = curColIdx < 0 and -curColIdx + cnt or curColIdx + cnt
    end
    if 0 < nextColIdx and nextColIdx <= #cols then
        api.nvim_win_set_cursor(0, {lnum, cols[nextColIdx] - 1})
    else
        local backwardColIdx, forwardColIdx = curColIdx, curColIdx
        if curColIdx < 0 then
            curColIdx = -curColIdx
            backwardColIdx, forwardColIdx = curColIdx + 1, curColIdx
        end
        Context:refreshHint(backwardColIdx, forwardColIdx)
    end
    fn.setcharsearch({char = char, forward = backward and 0 or 1, ['until'] = 0})
end

function M.move()
    if not Context:valid() then
        M.dispose()
        return
    end

    local winid = api.nvim_get_current_win()
    local cursor = api.nvim_win_get_cursor(winid)
    local lnum, col = unpack(cursor)
    local curColIdx = binarySearch(Context.cols, col + 1)
    if winid == Context.winid and lnum == Context.lnum and curColIdx > 0 then
        Context:refreshHint(curColIdx, curColIdx)
        Context:refreshCurrentWord(curColIdx)
        local fdo = vim.o.foldopen
        if fdo:find('all', 1, true) or fdo:find('hor', 1, true) then
            cmd('norm! zv')
        end
    else
        M.dispose()
    end
end

function M.dispose()
    local bufnr
    if Context.bufnr and Context.bufnr > 0 and api.nvim_buf_is_valid(Context.bufnr) then
        bufnr = Context.bufnr
    end
    Context:build()
    clearVirtText(bufnr)
    cmd('au! fFHighlight')
end

local function initialize(config)
    local ok, res = pcall(require, 'ffi')
    if ok then
        ffi = res
        ffi.cdef([[
            int get_keystroke(void *dummy_ptr);
        ]])
    end
    ns = api.nvim_create_namespace('fF-highlight')

    if not config.disable_keymap then
        local kopt = {noremap = true, silent = true}
        api.nvim_set_keymap('n', 'f', [[<Cmd>lua require('fFHighlight').findChar()<CR>]], kopt)
        api.nvim_set_keymap('x', 'f', [[<Cmd>lua require('fFHighlight').findChar()<CR>]], kopt)
        api.nvim_set_keymap('n', 'F', [[<Cmd>lua require('fFHighlight').findChar(true)<CR>]], kopt)
        api.nvim_set_keymap('x', 'F', [[<Cmd>lua require('fFHighlight').findChar(true)<CR>]], kopt)
    end
    disableWordsHl = config.disable_words_hl
    numberHintThreshold = config.number_hint_threshold

    cmd([[
        hi default fFHintChar ctermfg=yellow cterm=bold guifg=yellow gui=bold
        hi default fFHintNumber ctermfg=yellow cterm=bold guifg=yellow gui=bold
        hi default fFHintWords cterm=underline gui=underline
        hi default link fFHintCurrentWord fFHintWords
        hi default fFPromptSign ctermfg=yellow cterm=bold guifg=yellow gui=bold
    ]])

    wordRegex = vim.regex([[\k\+]])
    has09 = fn.has('nvim-0.9') == 1
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
    local config = vim.tbl_deep_extend('keep', opts or {}, {
        disable_keymap = false,
        disable_words_hl = false,
        number_hint_threshold = 3
    })

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
        number_hint_threshold = {
            config.number_hint_threshold, function(v)
            return type(v) == 'number' and v > 1
        end, 'a number greater than 1'
        },
        prompt_sign_define = {config.prompt_sign_define, 'table', true}
    })

    if not initialized then
        initialize(config)
        initialized = true
    end
end

return M
