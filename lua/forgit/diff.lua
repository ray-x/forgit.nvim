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
  local header = hunk_lines[1]
  local old_start, old_count, new_start, new_count = header:match("@@ %-(%d+),(%d+) %+(%d+),(%d+) @@")
  old_start, old_count = tonumber(old_start) or 1, tonumber(old_count) or 0
  new_start, new_count = tonumber(new_start) or 1, tonumber(new_count) or 0

  local hunk_data = {
    header = header,
    old_start = old_start,
    old_count = old_count,
    new_start = new_start,
    new_count = new_count,
    deletions = {}, -- { {line=..., after_context_idx=...}, ... }
    context = {},   -- { idx = buffer_line_number, text = ... }
    additions = {},
    word_diffs = {},
  }

  local cur_old = old_start
  local cur_new = new_start
  local context_idx = 0

  for i = 2, #hunk_lines do
    local line = hunk_lines[i]
    if line == "" then goto continue_parse end

    if line:match("^%[%-.*%-%]$") then
      -- Pure deletion line
      table.insert(hunk_data.deletions, {
        text = line:match("%[%-(.-)%-%]"),
        before_context = context_idx,
        hunk_idx = i,
      })
      cur_old = cur_old + 1
    elseif line:match("^%{%+.*%+%}$") then
      -- Pure addition line
      table.insert(hunk_data.additions, cur_new, line:match("%{%+(.-)%+%}"))
      cur_new = cur_new + 1
    elseif line:find("%[%-.-%-%]") or line:find("%{%+.-%+%}") then
      -- Word diff line (modification)
      table.insert(hunk_data.word_diffs, {
        pos = cur_new,
        content = line,
        is_list_item = line:match("^%s*%- "),
      })
      context_idx = context_idx + 1
      table.insert(hunk_data.context, {
        idx = context_idx,
        text = line,
        hunk_idx = i,
        new_linenr = cur_new,
      })
      cur_old = cur_old + 1
      cur_new = cur_new + 1
    else
      -- Context line
      context_idx = context_idx + 1
      table.insert(hunk_data.context, {
        idx = context_idx,
        text = line,
        hunk_idx = i,
        new_linenr = cur_new,
      })
      cur_old = cur_old + 1
      cur_new = cur_new + 1
    end
    ::continue_parse::
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
  local context = hunk_data.context

  -- Group deletions by before_context, preserving order
  local grouped = {}
  for _, del in ipairs(hunk_data.deletions) do
    grouped[del.before_context] = grouped[del.before_context] or {}
    table.insert(grouped[del.before_context], del)
  end

  -- Sort keys to render in correct order
  local keys = {}
  for k in pairs(grouped) do table.insert(keys, k) end
  table.sort(keys, function(a, b) return a < b end)

  for _, before_context in ipairs(keys) do
    local dels = grouped[before_context]
    local target_line
    if before_context == 0 then
      if #context > 0 then
        target_line = context[1].new_linenr - 1
      else
        target_line = hunk_data.new_start - 1
      end
    else
      if context[before_context + 1] then
        target_line = context[before_context + 1].new_linenr - 1
      else
        -- No context after: anchor after the last context line in the hunk
        if #context > 0 then
          target_line = context[#context].new_linenr
        else
          target_line = buf_line_count
        end
      end
    end
    target_line = math.max(target_line, 0)

    -- Render each deletion in reverse order so the first appears at the top
    for i = #dels, 1, -1 do
      local del = dels[i]
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, target_line, 0, {
        virt_lines = {{{del.text, "DiffDelete"}}},
        virt_lines_above = true,
      })
      render_count = render_count + 1
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

  -- Get all buffer lines for content matching
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, buf_line_count, false)

  for _, diff_data in ipairs(hunk_data.word_diffs) do
    local pos = diff_data.pos
    -- Unpack the content and metadata
    local content = diff_data.content
    local is_list_item = diff_data.is_list_item

    -- Calculate normalized content (what the line should look like after changes)
    local normalized_content = content
      :gsub("%[%-.-%-%]", "") -- Remove deleted text
      :gsub("%{%+(.-)%+%}", "%1") -- Replace additions with the added text

    -- Remove diff markers from normalized content for comparison
    local clean_content = normalized_content

    -- Find the actual line that matches this content, starting from pos-1
    local actual_line = pos
    local found_match = false

    -- Try to find an exact match in a window around the expected position
    local search_start = math.max(1, pos - 3)
    local search_end = math.min(buf_line_count, pos + 3)

    log(string.format("Searching for line match around line %d (range: %d-%d)",
      pos, search_start, search_end))

    -- For list items, we need to be more careful with matching
    if is_list_item then
      -- Extract just the content part after the list marker for matching
      local list_prefix = clean_content:match("^(%s*%- )")
      local content_without_marker = clean_content:gsub("^%s*%- ", "")

      for i = search_start, search_end do
        local buffer_line = buffer_lines[i] or ""
        local buffer_content = buffer_line:gsub("^%s*%- ", "")

        -- Compare the content part without the list marker
        if buffer_content and content_without_marker and
           buffer_content:find(content_without_marker, 1, true) then
          actual_line = i
          found_match = true
          log(string.format("Found list item match at line %d: '%s'", i, buffer_line))
          break
        end
      end
    else
      -- For regular lines, try a direct match first
      for i = search_start, search_end do
        local buffer_line = buffer_lines[i] or ""

        -- Try to match the normalized content (ignoring diff markers)
        -- We use a relaxed match that looks for the clean content as a substring
        if buffer_line and clean_content and
           buffer_line:find(clean_content:gsub("%%", "%%%%"), 1, true) then
          actual_line = i
          found_match = true
          log(string.format("Found direct match at line %d: '%s'", i, buffer_line))
          break
        end
      end

      -- If no match, try matching parts of the content (for links and other complex content)
      if not found_match then
        for i = search_start, search_end do
          local buffer_line = buffer_lines[i] or ""

          -- Extract key parts of the content for matching
          local key_parts = {}
          -- Find URL parts that might be consistent
          for url in clean_content:gmatch("%(([^%)]+)%)") do
            table.insert(key_parts, url)
          end
          -- Find text parts that might be consistent
          for text in clean_content:gmatch("%[([^%]]+)%]") do
            table.insert(key_parts, text)
          end

          local match_count = 0
          for _, part in ipairs(key_parts) do
            if buffer_line:find(part, 1, true) then
              match_count = match_count + 1
            end
          end

          -- If we match more than one key part, consider it a match
          if match_count >= 1 and #key_parts > 0 then
            actual_line = i
            found_match = true
            log(string.format("Found partial match at line %d: '%s'", i, buffer_line))
            break
          end
        end
      end
    end

    if not found_match then
      log(string.format("Warning: No match found for content near line %d: '%s'",
        pos, clean_content))
      -- Fall back to the original position
      actual_line = pos
    end

    -- Only continue if the position is valid in the buffer
    if actual_line > 0 and actual_line <= buf_line_count then
      -- Process word-level changes on the actual matching line
      log(string.format("Applying word diff to line %d (original pos: %d)", actual_line, pos))
      M.inline_diff_highlight(bufnr, actual_line, content)
      render_count = render_count + 1
    else
      log(string.format("Warning: Line %d is out of buffer range (1-%d)",
        actual_line, buf_line_count))
    end
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
  log("Current buffer line content: " .. line_content)

  -- Check for whole-line changes first
  if line:match("^%s*%[%-.*%-%]%s*$") then
    -- Full line deletion - show as virtual line
    local deleted = line:match("%[%-(.-)%-%]")
    log("Full line deletion: " .. deleted .. " |" .. current_line)
    
    -- Create a virtual line to show the deletion
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, current_line - 1, 0, {
      virt_lines = {{{deleted, "DiffDelete"}}},
      virt_lines_above = true, -- Default to above
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

  -- Handle markdown list items specially
  local is_markdown_list = line:match("^%s*%- ")
  local prefix_offset = 0

  if is_markdown_list then
    -- Calculate the offset from the list marker
    local list_marker = line:match("^(%s*%- )")
    if list_marker then
      prefix_offset = #list_marker
      log("List item detected with prefix: '" .. list_marker .. "', offset: " .. prefix_offset)
    end
  end

  -- Create a normalized version of the line to help find positions
  local normalized_line = line:gsub("%[%-.-%-%]", ""):gsub("%{%+(.-)%+%}", "%1")

  -- Check if the normalized line actually appears in the buffer
  -- This helps verify we're on the right line
  if not line_content:find(normalized_line:gsub("%%", "%%%%"), 1, true) and
     #normalized_line > 10 then -- Only check for substantial matches
    log("Warning: Normalized line doesn't match buffer content")
    log("  Normalized: " .. normalized_line)
    log("  Buffer: " .. line_content)

    -- Try to find key parts that should match
    local key_part = normalized_line:match("[^%s%.%(%)]+")
    if key_part and #key_part > 3 and not line_content:find(key_part, 1, true) then
      log("Warning: Key part '" .. key_part .. "' not found in buffer line")
      -- Consider finding a better matching line or adjusting position
    end
  end

  -- Process inline changes
  local pos = 1
  while pos <= #line do
    -- Find word diff patterns: [-old-]{+new+}
    local diff_start, diff_end = line:find("%[%-.-%-%]%{%+.-%+%}", pos)
    if diff_start then
      local full_match = line:sub(diff_start, diff_end)
      local deleted = full_match:match("%[%-(.-)%-%]")
      local added = full_match:match("%{%+(.-)%+%}")

      -- Calculate prefix accounting for any previous diffs and list markers
      local visible_prefix = line:sub(1, diff_start - 1)
                             :gsub("%[%-.-%-%]", "")
                             :gsub("%{%+(.-)%+%}", "%1")
      local start_col = #visible_prefix

      -- Try to locate the exact position in the buffer line
      local buffer_prefix = line_content:sub(1, math.min(start_col, #line_content))
      local expected_text = added or ""
      local expected_pos = start_col

      -- Check if the buffer prefix matches our calculated prefix
      if buffer_prefix ~= visible_prefix and #visible_prefix > 3 then
        log("Warning: Buffer prefix doesn't match calculated prefix")
        log("  Buffer prefix: '" .. buffer_prefix .. "'")
        log("  Calculated prefix: '" .. visible_prefix .. "'")

        -- Try to find the correct position by scanning for text after the change
        local after_change = line:sub(diff_end + 1):gsub("%[%-.-%-%]", ""):gsub("%{%+(.-)%+%}", "%1")
        local after_pos = line_content:find(after_change, 1, true)

        if after_pos and after_change ~= "" and #after_change > 3 then
          -- Adjust our starting position based on where the suffix appears
          expected_pos = after_pos - #expected_text
          log("Adjusted position using text after change to " .. expected_pos)
        end
      end

      -- Ensure column is within bounds of the line
      if expected_pos >= 0 and expected_pos < #line_content then
        -- Show deleted text as inline virtual text with DiffDelete
        log(string.format("Placing deletion at col %d: '%s'", expected_pos, deleted))
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, current_line - 1, expected_pos, {
          virt_text = {{deleted, "DiffDelete"}},
          virt_text_pos = "inline",
        })

        -- Highlight added text with DiffChange
        if added and added ~= "" and expected_pos + #added <= #line_content then
          log(string.format("Highlighting addition at col %d-%d: '%s'",
            expected_pos, expected_pos + #added, added))
          vim.api.nvim_buf_set_extmark(bufnr, ns_id, current_line - 1, expected_pos, {
            hl_group = "DiffChange",
            end_col = math.min(expected_pos + #added, #line_content),
          })
        end
      else
        log("Warning: Column position " .. expected_pos .. " is out of range for line " .. current_line)
      end

      pos = diff_end + 1
    -- Handle standalone deletion: [-deleted-]
    elseif line:find("%[%-.-%-%]", pos) == pos then
      local del_start, del_end = line:find("%[%-.-%-%]", pos)
      local deleted = line:sub(del_start + 2, del_end - 2)

      -- Calculate prefix accounting for any previous diffs and list markers
      local visible_prefix = line:sub(1, del_start - 1)
                             :gsub("%[%-.-%-%]", "")
                             :gsub("%{%+(.-)%+%}", "%1")
      local start_col = #visible_prefix

      -- Try to locate the exact position in the buffer line
      local buffer_prefix = line_content:sub(1, math.min(start_col, #line_content))

      -- Ensure column is within bounds of the line
      if start_col >= 0 and start_col < #line_content then
        -- Show deleted text as inline virtual text
        log(string.format("Placing standalone deletion at col %d: '%s'", start_col, deleted))
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, current_line - 1, start_col, {
          virt_text = {{deleted, "DiffDelete"}},
          virt_text_pos = "inline",
        })
      else
        log("Warning: Column position " .. start_col .. " is out of range for line " .. current_line)
      end

      pos = del_end + 1
    -- Handle standalone addition: {+added+}
    elseif line:find("%{%+.-%+%}", pos) then
      local add_start, add_end = line:find("%{%+.-%+%}", pos)
      local added = line:sub(add_start + 2, add_end - 2)

      -- Calculate prefix accounting for any previous diffs and list markers
      local visible_prefix = line:sub(1, add_start - 1)
                             :gsub("%[%-.-%-%]", "")
                             :gsub("%{%+(.-)%+%}", "%1")
      local start_col = #visible_prefix

      -- Try to locate the exact position in the buffer line
      local buffer_prefix = line_content:sub(1, math.min(start_col, #line_content))

      -- Ensure column is within bounds of the line
      if start_col >= 0 and start_col < #line_content then
        -- Highlight added text
        if start_col + #added <= #line_content then
          log(string.format("Highlighting standalone addition at col %d-%d: '%s'",
            start_col, start_col + #added, added))
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
    log(res.stdout)

    -- Process the diff output one hunk at a time
    local i = 1
    local hunk_file
    while i <= #lines do
      local line = lines[i]
      -- find hunk file header
      if line:match("^diff %-%-git") then
        -- Found a new file header
        hunk_file = line:match("b/(.+)$")
        log("Found hunk file: " .. line  .. hunk_file)
        -- Get the next line for the buffer number
      end

      if line:match("^@@") then
        -- Found hunk header
        local start_line = tonumber(line:match("%+(%d+)")) or 1
        local hunk_header = line

        -- Collect all lines in this hunk
        local hunk_lines = { line } -- Start with the header
        local j = i + 1
        while j <= #lines and not lines[j]:match("^@@") and not lines[j]:match("^diff %-%-git") do
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
          filename = hunk_file,
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

      -- setup filename and bufnr for qf
      for i, item in ipairs(qf_items) do
        local bufnr = vim.fn.bufnr(item.filename or 0)
        if bufnr >= 0 then
          item.bufnr = bufnr
        end
      end
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
