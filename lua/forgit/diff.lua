local utils = require('forgit.utils')
local log = utils.log
local M = {}

-- Namespace for diff extmarks
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
  if #M.branches > 0 then
    return M.branches
  end
  local branches = {}
  vim.system({ "git", "branch", "--list" }, { text = true }, function(res)
    if res.code ~= 0 then
      vim.notify("Failed to get branches: " .. tostring(res.code) .. tostring(res.stderr), vim.log.levels.WARN)
      return branches
    end
    for _, line in ipairs(split_lines(res.stdout)) do
      local branch = line:match("^%s*%*?%s*(.+)$")
      if branch then
        table.insert(branches, branch)
      end
    end
    M.branches = branches
  end)
  return branches
end

M.branches = {}

-- Clear all extmarks in a buffer
local function clear_diff_highlights(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
end

-- Create a testable module structure
M.internal = {}  -- For test access to internal functions

-- Parse a git diff hunk into a structured representation
function M.internal.parse_hunk(hunk_lines)
  -- Extract header information
  local header = hunk_lines[1]
  local old_start, old_count, new_start, new_count = header:match("@@ %-(%d+),(%d+) %+(%d+),(%d+) @@")
  old_start, old_count = tonumber(old_start) or 1, tonumber(old_count) or 0
  new_start, new_count = tonumber(new_start) or 1, tonumber(new_count) or 0

  -- Store header info
  local hunk_data = {
    header = header,
    old_start = old_start,
    old_count = old_count,
    new_start = new_start,
    new_count = new_count,
    deletions = {}, -- Maps positions to deleted lines
    additions = {}, -- Maps positions to added lines
    word_diffs = {} -- Maps positions to word diff lines
  }

  -- Process the hunk line by line
  local cur_old = old_start
  local cur_new = new_start

  for i = 2, #hunk_lines do
    local line = hunk_lines[i]
    if line == "" then goto continue_parse end

    local first_char = line:sub(1, 1)

    if first_char == "-" then
      -- Deletion line
      if not hunk_data.deletions[cur_new] then
        hunk_data.deletions[cur_new] = {}
      end
      table.insert(hunk_data.deletions[cur_new], line:sub(2))
      cur_old = cur_old + 1
      -- Do NOT increment cur_new for deletions
    elseif first_char == "+" then
      -- Addition line
      hunk_data.additions[cur_new] = line:sub(2)
      cur_new = cur_new + 1
    elseif line:match("^%s*%{%+.*%+%}$") then
      -- Special case: word diff that's a complete line addition
      local content = line:match("%{%+(.-)%+%}")
      hunk_data.additions[cur_new] = content
      cur_new = cur_new + 1
    elseif line:match("^%s*%[%-.*%-%]$") then
      -- Special case: word diff that's a complete line deletion
      local content = line:match("%[%-(.-)%-%]")
      if not hunk_data.deletions[cur_new] then
        hunk_data.deletions[cur_new] = {}
      end
      table.insert(hunk_data.deletions[cur_new], content)
      cur_old = cur_old + 1
    elseif line:find("%[%-.-%-%]") or line:find("%{%+.-%+%}") then
      -- Mixed word diff line
      hunk_data.word_diffs[cur_new] = line
      cur_old = cur_old + 1
      cur_new = cur_new + 1
    else
      -- Context line (unchanged)
      cur_old = cur_old + 1
      cur_new = cur_new + 1
    end

    ::continue_parse::
  end

  -- Handle end-of-file deletions
  for pos, _ in pairs(hunk_data.deletions) do
    if tonumber(pos) and tonumber(pos) > new_start + new_count - 1 then
      -- Move to EOF section
      hunk_data.deletions["EOF"] = hunk_data.deletions[pos]
      hunk_data.deletions[pos] = nil
    end
  end

  return hunk_data
end

-- Validate a buffer line for rendering
function M.internal.validate_buffer_position(bufnr, line, col)
  local buf_line_count = vim.api.nvim_buf_line_count(bufnr)

  if line <= 0 or line > buf_line_count then
    return false, string.format("Line %d is out of buffer range (1-%d)", line, buf_line_count)
  end

  if col then
    local line_content = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1] or ""
    if col < 0 or col > #line_content then
      return false, string.format("Column %d is out of range (0-%d) for line %d",
        col, #line_content, line)
    end
  end

  return true, nil
end

-- Render deletions from parsed hunk data
function M.internal.render_deletions(bufnr, hunk_data)
  local buf_line_count = vim.api.nvim_buf_line_count(bufnr)
  local render_count = 0

  -- Get the content of the buffer for context checking
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, buf_line_count, false)

  -- Render regular deletions
  for pos, del_lines in pairs(hunk_data.deletions) do
    if pos == "EOF" then
      -- Handle EOF deletions
      local virt_lines = {}
      for _, line in ipairs(del_lines) do
        table.insert(virt_lines, {{line, "DiffDelete"}})
      end

      -- Place at the very end of the buffer
      local end_line = math.max(0, buf_line_count - 1)

      -- Place the virtual lines BELOW (not above) the last line
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, end_line, 0, {
        virt_lines = virt_lines,
        virt_lines_above = false,
      })
      render_count = render_count + #del_lines
    else
      -- Normal deletions
      local virt_lines = {}
      for _, line in ipairs(del_lines) do
        table.insert(virt_lines, {{line, "DiffDelete"}})
      end

      -- Calculate safe position (bounded to actual buffer)
      local target_line = math.min(tonumber(pos) - 1, buf_line_count - 1)
      target_line = math.max(target_line, 0)

      -- Check context to determine if we should place above or below
      local place_above = true

      -- Get the line at the target position
      local line_content = buffer_lines[target_line + 1] or ""

      -- If this line is a function declaration or an opening brace, place below
      if line_content:match("^%s*func%s+") or line_content:match("%{%s*$") then
        place_above = false
        log(string.format("Placing deletions AFTER the function declaration at line %d", target_line + 1))
      else
        log(string.format("Placing deletions BEFORE line %d", target_line + 1))
      end

      -- Place the virtual lines
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, target_line, 0, {
        virt_lines = virt_lines,
        virt_lines_above = place_above,
      })
      render_count = render_count + #del_lines
    end
  end

  return render_count
end

-- Render additions from parsed hunk data
function M.internal.render_additions(bufnr, hunk_data)
  local buf_line_count = vim.api.nvim_buf_line_count(bufnr)
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, buf_line_count, false)
  local render_count = 0

  for pos, content in pairs(hunk_data.additions) do
    -- Only continue if the position is valid in the buffer
    if pos > buf_line_count then
      goto continue_add
    end

    -- Pure addition - check if it matches the current content in the buffer
    local buffer_line = buffer_lines[pos]

    if buffer_line == content then
      -- This is a pure addition - highlight the entire line
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, pos - 1, 0, {
        line_hl_group = "DiffAdd",
      })
      render_count = render_count + 1
    end

    ::continue_add::
  end

  return render_count
end

-- Render word diffs from parsed hunk data
function M.internal.render_word_diffs(bufnr, hunk_data)
  local buf_line_count = vim.api.nvim_buf_line_count(bufnr)
  local render_count = 0

  for pos, content in pairs(hunk_data.word_diffs) do
    -- Only continue if the position is valid in the buffer
    if pos > buf_line_count then
      goto continue_word
    end

    -- Process word-level changes
    M.inline_diff_highlight(bufnr, pos, content)
    render_count = render_count + 1

    ::continue_word::
  end

  return render_count
end

-- Refactored render_hunk function that uses the new structure
function M.render_hunk(hunk)
  local bufnr = hunk.bufnr
  local hunk_lines = hunk.user_data.hunk

  -- Clear previous highlights
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Parse the hunk into a structured format
  local hunk_data = M.internal.parse_hunk(hunk_lines)

  log(string.format("Processing hunk: %s (old: %d-%d, new: %d-%d)",
    hunk_data.header,
    hunk_data.old_start, hunk_data.old_start + hunk_data.old_count - 1,
    hunk_data.new_start, hunk_data.new_start + hunk_data.new_count - 1))

  -- Render all elements
  local del_count = M.internal.render_deletions(bufnr, hunk_data)
  local add_count = M.internal.render_additions(bufnr, hunk_data)
  local word_count = M.internal.render_word_diffs(bufnr, hunk_data)

  log(string.format("Rendered %d deletions, %d additions, %d word diffs",
    del_count, add_count, word_count))

  return del_count + add_count + word_count -- Return total changes for testing
end

-- Test helper that can be used in unit tests
function M.test_hunk_render(hunk_lines, buffer_lines)
  -- Create a scratch buffer for testing
  local bufnr = vim.api.nvim_create_buf(false, true)

  -- Set up buffer content
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, buffer_lines)

  -- Parse and render the hunk
  local hunk_data = M.internal.parse_hunk(hunk_lines)

  -- Create a mock hunk entry
  local mock_hunk = {
    bufnr = bufnr,
    user_data = {
      hunk = hunk_lines
    }
  }

  -- Render and get counts
  local result = M.render_hunk(mock_hunk)

  -- Collect all extmarks for verification
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {details = true})

  -- Clean up
  vim.api.nvim_buf_delete(bufnr, {force = true})

  -- Return results for test verification
  return {
    hunk_data = hunk_data,
    render_count = result,
    extmarks = extmarks
  }
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
    elseif line:find("%s%{%+.-%+%}", pos) == pos then
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
  
  -- Determine which files to diff
  local files = {}
  local diff_all = true  -- Default to diff all files
  
  if opts.files and #opts.files > 0 then
    -- Process specific files
    diff_all = false  -- We're diffing specific files
    for _, file in ipairs(opts.files) do
      if file == "%" then
        local current_file = vim.api.nvim_buf_get_name(current_buf)
        if current_file == "" then
          vim.notify("Cannot diff an unnamed buffer with '%'", vim.log.levels.ERROR)
          return
        end
        table.insert(files, current_file)
      elseif file ~= "" then  -- Skip empty strings
        table.insert(files, file)
      end
    end
  end
  
  -- Clear previous diff highlights for the current buffer
  clear_diff_highlights(current_buf)
  
  -- Prepare the git command
  local git_cmd = {"git", "--no-pager", "diff"}
  
  -- Add target if specified and not empty
  if target_branch and target_branch ~= "" then
    table.insert(git_cmd, target_branch)
  end
  
  -- Add other options
  table.insert(git_cmd, "--word-diff=plain")
  table.insert(git_cmd, "--diff-algorithm=myers")
  
  -- Add files if specific files are requested
  if not diff_all and #files > 0 then
    table.insert(git_cmd, "--")
    for _, file in ipairs(files) do
      table.insert(git_cmd, file)
    end
  end
  
  log("Running git command: " .. table.concat(git_cmd, " "))
  
  -- Run the git diff command
  vim.system(git_cmd, { text = true }, function(res)
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

    -- Just update the title to show which branch and files were compared
    local file_info = ""
    if #files == 1 then
      file_info = " " .. vim.fn.fnamemodify(files[1], ":~:.")
    elseif #files > 1 then
      file_info = " (" .. #files .. " files)"
    end

    local title = "GitDiff: " .. (target_branch or '') .. file_info

    -- Render all hunks and populate quickfix
    vim.schedule(function()
      vim.fn.setqflist({}, " ", {
        title = title,
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
  -- Parse command arguments to handle file specifications
  local function parse_args(args)
    local target_branch = nil
    local files = {}
    local parts = vim.split(args, "%s+")
    
    local i = 1
    while i <= #parts do
      local part = parts[i]
      
      -- Skip empty parts
      if part == "" then
        i = i + 1
        goto continue
      end
      
      -- Check for file specifier
      if part == "--" then
        -- Everything after -- is a file
        for j = i + 1, #parts do
          if parts[j] and parts[j] ~= "" then
            table.insert(files, parts[j])
          end
        end
        break
      elseif part == "%" then
        -- Current file
        table.insert(files, "%")
      -- Check if this looks like a file path or pattern rather than a branch
      elseif (not target_branch) and (part:find("/") or part:find("%.") or part:find("*")) then
        -- This is probably a file, not a branch
        table.insert(files, part)
      elseif not target_branch then
        -- First non-special argument is assumed to be a target branch
        target_branch = part
      else
        -- Additional arguments are assumed to be files
        table.insert(files, part)
      end
      
      ::continue::
      i = i + 1
    end
    
    return {
      target = target_branch,
      files = #files > 0 and files or nil
    }
  end

  vim.api.nvim_create_user_command('GitDiff', function(opts)
    local parsed = parse_args(opts.args)
    -- No default value - let git diff use its default behavior
    local target = parsed.target

    -- Run git diff with parsed arguments
    M.run_git_diff(target, {files = parsed.files})
  end, {
    nargs = "*",
    complete = branch_complete,
    desc = "Show git diff with optional branch and file arguments"
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
