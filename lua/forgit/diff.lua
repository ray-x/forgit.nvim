local utils = require('forgit.utils')
local log = utils.log
local M = {}

-- Namespace for extmarks
local ns_id = vim.api.nvim_create_namespace('git_diff_render')

-- Helper function to split text into lines
local function split_lines(s)
  local t = {}
  for line in s:gmatch('([^\n]*)\n?') do
    table.insert(t, line)
  end
  return t
end

-- Get all git branches for command completion
local function branch_complete()
  return table.concat(vim.fn.systemlist("git branch --format='%(refname:short)'"), '\n')
end

-- Clear all extmarks in a buffer
local function clear_diff_highlights(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end
function M.render_hunk(hunk)
  local bufnr = hunk.bufnr
  local hunk_lines = hunk.user_data.hunk
  
  -- Clear previous highlights 
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  
  -- Parse hunk header for position info
  local header = hunk_lines[1]
  local old_start, old_count, new_start, new_count = header:match("@@ %-(%d+),(%d+) %+(%d+),(%d+) @@")
  old_start, old_count = tonumber(old_start) or 1, tonumber(old_count) or 0
  new_start, new_count = tonumber(new_start) or 1, tonumber(new_count) or 0
  
  log(string.format("Processing hunk: %s (old: %d-%d, new: %d-%d)", 
    header, old_start, old_start + old_count - 1, new_start, new_start + new_count - 1))
  
  -- Get the actual buffer content
  local buf_line_count = vim.api.nvim_buf_line_count(bufnr)
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, buf_line_count, false)
  
  -- Get a map of actual lines in the current buffer
  local buffer_content_map = {}
  for i, line in ipairs(buffer_lines) do
    buffer_content_map[i] = line
  end
  
  -- Process the diff
  -- We need to map between new file line numbers and new file content
  local new_line_map = {}  -- Maps new file line numbers to actual content
  
  -- Current positions while processing the diff
  local cur_old = old_start
  local cur_new = new_start
  
  -- First, gather information about deletions
  local deletions = {}  -- Maps new file positions to deleted lines
  
  -- Helper to add a deletion at the current position
  local function add_deletion(content)
    -- Special handling for end-of-file deletions
    local target_pos = cur_new
    
    -- If we're at the end of the file, mark it for special handling
    if target_pos > new_start + new_count - 1 then
      log(string.format("End-of-file deletion detected at position %d (file has only %d lines)", 
        target_pos, new_start + new_count - 1))
      -- Use a special "EOF" marker in the position
      target_pos = "EOF"
    end
    
    if target_pos == "EOF" then
      -- For EOF deletions, always put them after the last line
      if not deletions["EOF"] then
        deletions["EOF"] = {}
      end
      table.insert(deletions["EOF"], content)
      log(string.format("Marking EOF deletion: %s", content))
    else
      -- Normal deletion
      if not deletions[target_pos] then
        deletions[target_pos] = {}
      end
      table.insert(deletions[target_pos], content)
      log(string.format("Marking deletion at new file position %d: %s", target_pos, content))
    end
  end
  
  -- Process each line in the hunk
  for i = 2, #hunk_lines do
    local line = hunk_lines[i]
    if line == "" then goto continue_scan end
    
    local first_char = line:sub(1, 1)
    
    if first_char == "-" then
      -- Deletion line
      add_deletion(line:sub(2))
      cur_old = cur_old + 1
      -- Do NOT increment cur_new for deletions
    elseif first_char == "+" then
      -- Addition line
      new_line_map[cur_new] = line:sub(2)
      cur_old = cur_old  -- No change to old file position
      cur_new = cur_new + 1
    elseif line:match("^%[%-.*%-%]$") then
      -- Special case: word diff that's a complete line deletion
      local content = line:match("%[%-(.-)%-%]")
      add_deletion(content)
      cur_old = cur_old + 1
      -- Do NOT increment cur_new for deletions
    elseif line:match("^%{%+.*%+%}$") then
      -- Special case: word diff that's a complete line addition
      local content = line:match("%{%+(.-)%+%}")
      new_line_map[cur_new] = content
      cur_old = cur_old  -- No change to old file position
      cur_new = cur_new + 1
    elseif line:find("%[%-.-%-%]") or line:find("%{%+.-%+%}") then
      -- Word diff (mixed changes)
      new_line_map[cur_new] = line
      cur_old = cur_old + 1
      cur_new = cur_new + 1
    else
      -- Context line (unchanged)
      new_line_map[cur_new] = line
      cur_old = cur_old + 1
      cur_new = cur_new + 1
    end
    
    ::continue_scan::
  end
  
  -- Log our findings
  log("Deletions by position:")
  for pos, del_lines in pairs(deletions) do
    log(string.format("  Position %s: %d lines", tostring(pos), #del_lines))
    for i, line in ipairs(del_lines) do
      log(string.format("    [%d] %s", i, line))
    end
  end
  
  -- Render normal deletions as virtual lines
  for pos, del_lines in pairs(deletions) do
    -- Skip EOF deletions - we'll handle those separately
    if pos == "EOF" then goto continue_render end
    
    -- Convert to virtual lines format
    local virt_lines = {}
    for _, line in ipairs(del_lines) do
      table.insert(virt_lines, {{line, "DiffDelete"}})
    end
    
    -- Calculate safe position (bounded to actual buffer)
    local target_line = math.min(tonumber(pos) - 1, buf_line_count - 1)
    target_line = math.max(target_line, 0)
    
    log(string.format("Rendering %d deletion(s) at new file line %s (buffer line %d)", 
      #del_lines, tostring(pos), target_line + 1))
    
    -- Place the virtual lines
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, target_line, 0, {
      virt_lines = virt_lines,
      virt_lines_above = true,
    })
    
    ::continue_render::
  end
  
  -- Handle EOF deletions separately - always put at the end of the file
  if deletions["EOF"] then
    local virt_lines = {}
    for _, line in ipairs(deletions["EOF"]) do
      table.insert(virt_lines, {{line, "DiffDelete"}})
    end
    
    -- Place at the very end of the buffer
    local end_line = math.max(0, buf_line_count - 1)
    
    log(string.format("Rendering %d EOF deletion(s) after the last line (buffer line %d)", 
      #deletions["EOF"], end_line + 1))
    
    -- Place the virtual lines BELOW (not above) the last line
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, end_line, 0, {
      virt_lines = virt_lines,
      virt_lines_above = false, -- This is the key difference - show below
    })
  end
  
  -- Render additions and word diffs
  for pos, content in pairs(new_line_map) do
    -- Skip positions beyond the buffer
    if pos > buf_line_count then goto continue_render2 end
    
    -- Check if this is a word diff line
    if content:find("%[%-.-%-%]") or content:find("%{%+.-%+%}") then
      -- Process word-level changes
      log(string.format("Processing word diff at line %d: %s", pos, content))
      M.inline_diff_highlight(bufnr, pos, content)
    else
      -- Check if this line was added (by looking for it in the buffer)
      local actual_line = buffer_lines[pos]
      if actual_line == content then
        -- Line exists unchanged in buffer - check if it's part of the additions
        local is_addition = false
        for i = 2, #hunk_lines do
          local line = hunk_lines[i]
          if line:sub(1, 1) == "+" and line:sub(2) == content then
            is_addition = true
            break
          end
        end
        
        if is_addition then
          -- Highlight as addition
          log(string.format("Highlighting addition at line %d", pos))
          vim.api.nvim_buf_set_extmark(bufnr, ns_id, pos - 1, 0, {
            line_hl_group = "DiffAdd",
          })
        end
      end
    end
    
    ::continue_render2::
  end
end

function M.inline_diff_highlight(bufnr, current_line, line)
  log("Inline diff at line " .. current_line .. ": " .. line)
  
  -- Get buffer line count for bounds checking
  local buf_line_count = vim.api.nvim_buf_line_count(bufnr)
  
  -- Check if the current line is within valid buffer bounds
  if current_line <= 0 or current_line > buf_line_count then
    log("Warning: Cannot highlight line " .. current_line .. " - out of buffer range (1-" .. buf_line_count .. ")")
    return
  end
  
  -- Get the content of the current line in the buffer
  local line_content = vim.api.nvim_buf_get_lines(bufnr, current_line - 1, current_line, false)[1] or ""
  
  -- Check for whole-line changes first
  if line:match("^%s*%[%-.*%-%]$") then
    -- Full line deletion - show as virtual line
    local deleted = line:match("%[%-(.-)%-%]")
    log("Full line deletion: " .. deleted .. " |" .. current_line)
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, current_line - 1, 0, {
      virt_lines = {{{deleted, "DiffDelete"}}},
      virt_lines_above = true,
    })
    return
  elseif line:match("^%s*%{%+.*%+%}$") then
    -- Full line addition - highlight entire line
    log("Full line addition: " .. line .. " |" .. current_line)
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, current_line - 1, 0, {
      line_hl_group = "DiffAdd",
    })
    return
  end
  
  -- Process inline changes
  local pos = 1
  while pos <= #line do
    -- Handle combined changes: [-old-]{+new+}
    local repl_start, repl_end = line:find("%[%-.-%-%]%{%+.-%+%}", pos)
    if repl_start then
      local full_match = line:sub(repl_start, repl_end)
      local deleted = full_match:match("%[%-(.-)%-%]")
      local added = full_match:match("%{%+(.-)%+%}")
      
      -- Find position in buffer
      local prefix = line:sub(1, repl_start - 1):gsub("%[%-.-%-%]", ""):gsub("%{%+(.-)%+%}", "%1")
      local start_col = #prefix
      
      -- Ensure column is within bounds of the line
      if start_col < #line_content then
        -- Show deleted text as inline virtual text with DiffDelete
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, current_line - 1, start_col, {
          virt_text = {{deleted, "DiffDelete"}},
          virt_text_pos = "inline",
        })
        
        -- Highlight added text with DiffChange
        if start_col + #added <= #line_content then
          vim.api.nvim_buf_set_extmark(bufnr, ns_id, current_line - 1, start_col, {
            hl_group = "DiffChange",
            end_col = math.min(start_col + #added, #line_content),
          })
        end
      else
        log("Warning: Column position " .. start_col .. " is out of range for line " .. current_line)
      end
      
      pos = repl_end + 1
    
    -- Handle standalone deletion: [-deleted-]
    elseif line:find("%[%-.-%-%]", pos) == pos then
      local del_start, del_end = line:find("%[%-.-%-%]", pos)
      local deleted = line:sub(del_start + 2, del_end - 2)
      
      -- Find position in buffer
      local prefix = line:sub(1, del_start - 1):gsub("%[%-.-%-%]", ""):gsub("%{%+(.-)%+%}", "%1")
      local start_col = #prefix
      
      -- Ensure column is within bounds of the line
      if start_col < #line_content then
        -- Show deleted text as inline virtual text
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, current_line - 1, start_col, {
          virt_text = {{deleted, "DiffDelete"}},
          virt_text_pos = "inline",
        })
      else
        log("Warning: Column position " .. start_col .. " is out of range for line " .. current_line)
      end
      
      pos = del_end + 1
    
    -- Handle standalone addition: {+added+}
    elseif line:find("%{%+.-%+%}", pos) == pos then
      local add_start, add_end = line:find("%{%+.-%+%}", pos)
      local added = line:sub(add_start + 2, add_end - 2)
      
      -- Find position in buffer
      local prefix = line:sub(1, add_start - 1):gsub("%[%-.-%-%]", ""):gsub("%{%+(.-)%+%}", "%1")
      local start_col = #prefix
      
      -- Ensure column is within bounds of the line
      if start_col < #line_content then
        -- Highlight added text
        if start_col + #added <= #line_content then
          vim.api.nvim_buf_set_extmark(bufnr, ns_id, current_line - 1, start_col, {
            hl_group = "DiffAdd",
            end_col = math.min(start_col + #added, #line_content),
          })
        else
          log("Warning: Addition end column is out of range")
          -- Highlight what we can
          vim.api.nvim_buf_set_extmark(bufnr, ns_id, current_line - 1, start_col, {
            hl_group = "DiffAdd",
            end_col = #line_content,
          })
        end
      else
        log("Warning: Column position " .. start_col .. " is out of range for line " .. current_line)
      end
      
      pos = add_end + 1
    else
      -- No pattern match, move forward
      pos = pos + 1
    end
  end
end


-- Run git diff and parse the results
function M.run_git_diff(target_branch, opts)
  opts = opts or {}
  local current_buf = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(current_buf)

  if current_file == "" then
    vim.notify("Cannot diff an unnamed buffer", vim.log.levels.ERROR)
    return
  end

  -- Clear previous diff highlights
  clear_diff_highlights(current_buf)

  vim.system({
    "git", "--no-pager", "diff", target_branch, "--word-diff=plain", "--diff-algorithm=myers", "--", current_file
  }, { text = true }, function(res)
    if res.code ~= 0 then
      return vim.schedule(function()
        vim.notify("GitDiff failed: " .. res.stderr, vim.log.levels.ERROR)
      end)
    end

    if res.stdout == "" then
      return vim.schedule(function()
        vim.notify("No differences found", vim.log.levels.INFO)
      end)
    end

    local lines = split_lines(res.stdout)
    local qf_items = {}

    -- Process the diff output one hunk at a time
    local i = 1
    while i <= #lines do
      local line = lines[i]

      if line:match("^@@") then
        -- Found hunk header
        local start_line = tonumber(line:match("%+(%d+)")) or 1
        local hunk_header = line
        
        -- Collect all lines in this hunk
        local hunk_lines = { line } -- Start with the header
        local j = i + 1
        while j <= #lines and not lines[j]:match("^@@") do
          table.insert(hunk_lines, lines[j])
          j = j + 1
        end
        
        -- Find first actual change line in hunk
        local first_change_line = start_line
        local offset = 0
        for k = 2, #hunk_lines do
          local hline = hunk_lines[k]
          if hline == "" then
            -- Do nothing for empty lines
          elseif hline:find("%[%-.-%-%]") or hline:find("%{%+.-%+%}") then
            -- Word diff line - this is a change
            first_change_line = start_line + offset
            break
          elseif hline:sub(1, 1) == "+" then
            -- Addition line
            first_change_line = start_line + offset
            break
          elseif hline:sub(1, 1) == "-" then
            -- Deletion line
            first_change_line = start_line + offset
            break
          else
            -- Context line
            offset = offset + 1
          end
        end
        
        -- Create a quickfix item for the entire hunk
        table.insert(qf_items, {
          filename = current_file,
          bufnr = current_buf,
          lnum = first_change_line,
          col = 1,
          text = hunk_header,
          user_data = {
            hunk = hunk_lines,
            first_change_line = first_change_line,
            start_line = start_line,
          },
        })
        
        i = j -- Move to next hunk
      else
        i = i + 1
      end
    end

    -- Render all hunks and populate quickfix
    vim.schedule(function()
      vim.fn.setqflist({}, " ", {
        title = "GitDiff: " .. target_branch,
        items = qf_items,
      })
      vim.cmd("copen")

      -- Render first hunk immediately
      if #qf_items > 0 then
        M.render_hunk(qf_items[1])
      end

      vim.notify("Rendered diff with " .. #qf_items .. " hunks", vim.log.levels.INFO)
    end)
  end)
end

-- Clear diff highlights from current buffer
function M.clear_diff()
  local bufnr = vim.api.nvim_get_current_buf()
  clear_diff_highlights(bufnr)
  vim.notify("Cleared diff highlights", vim.log.levels.INFO)
end

-- Setup quickfix window mappings
function M.setup_qf_mappings()
  -- Only run once per window
  if vim.b.gitdiff_qf_mapped then return end
  vim.b.gitdiff_qf_mapped = true

  local opts = { silent = true, nowait = true, buffer = true }

  -- Helper function to handle navigation
  local function on_cursor_move()
    local idx = vim.fn.line('.')
    local qf = vim.fn.getqflist({ idx = idx, items = 0 })
    if not qf or not qf.items or #qf.items == 0 or not qf.items[1] then
      return
    end

    local entry = qf.items[1]
    if not entry.user_data or not entry.user_data.hunk then
      return
    end

    -- Get the buffer using bufnr directly from the entry
    local bufnr
    if entry.bufnr and entry.bufnr > 0 then
      bufnr = entry.bufnr
    else
      -- Fallback to getting buffer by filename
      if not entry.filename or entry.filename == "" then
        vim.notify("Invalid quickfix entry: missing filename", vim.log.levels.ERROR)
        return
      end
      bufnr = vim.fn.bufnr(entry.filename)
      if bufnr == -1 then
        -- Open the file if it's not open
        bufnr = vim.fn.bufadd(entry.filename)
        vim.fn.bufload(bufnr)
      end
    end

    -- Clear previous highlights
    clear_diff_highlights(bufnr)

    -- Render the hunk
    local start_line = entry.user_data.start_line
    M.render_hunk(entry)

    -- Jump to the correct location in a split if not already visible
    local winid = vim.fn.bufwinid(bufnr)
    if winid == -1 then
      -- Save current quickfix window ID
      local qf_winid = vim.api.nvim_get_current_win()

      -- Open file in a split
      vim.cmd("wincmd s")
      vim.cmd("buffer " .. bufnr)

      -- Set cursor position
      vim.api.nvim_win_set_cursor(0, { entry.lnum, entry.col - 1 })

      -- Return to quickfix window
      vim.api.nvim_set_current_win(qf_winid)
    else
      -- Just update cursor in existing window
      vim.api.nvim_win_set_cursor(winid, { entry.lnum, entry.col - 1 })
    end
  end

  -- <CR> - close qf and jump to file
  vim.keymap.set('n', '<CR>', function()
    local idx = vim.fn.line('.')
    local qf = vim.fn.getqflist({ idx = idx, items = 0 })
    if not qf or not qf.items or #qf.items == 0 or not qf.items[1] then
      return
    end

    local entry = qf.items[1]
    if not entry.bufnr or entry.bufnr <= 0 then
      if not entry.filename or entry.filename == "" then
        vim.notify("Invalid quickfix entry: missing filename", vim.log.levels.ERROR)
        return
      end

      -- Try to get or create the buffer
      local bufnr = vim.fn.bufnr(entry.filename)
      if bufnr == -1 then
        vim.cmd("edit " .. vim.fn.fnameescape(entry.filename))
        bufnr = vim.fn.bufnr(entry.filename)
      end
      entry.bufnr = bufnr
    end

    vim.cmd("cclose")
    vim.cmd("buffer " .. entry.bufnr)
    vim.api.nvim_win_set_cursor(0, { entry.lnum, entry.col - 1 })

    -- Render diff at the position
    if entry.user_data and entry.user_data.hunk then
      local start_line = entry.user_data.start_line
      M.render_hunk(entry)
    end
  end, opts)

  -- Cursor movement triggers diff rendering
  vim.keymap.set('n', 'j', function()
    vim.cmd("normal! j")
    on_cursor_move()
  end, opts)

  vim.keymap.set('n', 'k', function()
    vim.cmd("normal! k")
    on_cursor_move()
  end, opts)

  -- Initial render
  on_cursor_move()
end

-- Set up user commands and autocommands
function M.setup()
  vim.api.nvim_create_user_command('GitDiff', function(opts)
    if opts.args == '' then
      vim.notify('Usage: :GitDiff <branch>', vim.log.levels.WARN)
      return
    end
    M.run_git_diff(opts.args)
  end, {
    nargs = 1,
    complete = branch_complete,
  })

  vim.api.nvim_create_user_command('GitDiffClear', function()
    M.clear_diff()
  end, {})

  -- Autocommand to set up quickfix mappings when it opens
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "qf",
    callback = function()
      -- Only set up if this is a GitDiff quickfix list
      local qf = vim.fn.getqflist({ title = 0 })
      if qf.title and qf.title:match("^GitDiff:") then
        M.setup_qf_mappings()
      end
    end,
    desc = "GitDiff: Map navigation in quickfix",
  })

  -- Define quickfixtextfunc for better rendering
  _G.gitdiff_qftf = function(info)
    local qf = vim.fn.getqflist({ id = info.id, items = 0 })
    local items = qf.items

    local out = {}
    for idx = info.start_idx, info.end_idx do
      local e = items[idx]
      local ud = e.user_data

      -- Make sure we have a valid filename
      local filename = e.filename
      if not filename or filename == "" then
        if e.bufnr and e.bufnr > 0 then
          filename = vim.api.nvim_buf_get_name(e.bufnr)
        end
        if not filename or filename == "" then
          filename = "<unknown>"
        end
      end

      if ud and ud.hunk_header then
        local file_part = string.format('%s:%d │', vim.fn.fnamemodify(filename, ':~:.'), e.lnum)
        local header = file_part .. ' ' .. ud.hunk_header
        table.insert(out, header)
      else
        table.insert(out, string.format('%s:%d │ %s', vim.fn.fnamemodify(filename, ':~:.'), e.lnum, e.text or ''))
      end
    end

    return out
  end

  -- Set quickfixtextfunc globally
  vim.o.quickfixtextfunc = '{info -> v:lua.gitdiff_qftf(info)}'
end

return M
