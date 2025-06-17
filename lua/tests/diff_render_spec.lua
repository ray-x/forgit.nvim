local _ = require('plenary/busted')

local eq = assert.are.same
local cur_dir = vim.fn.expand('%:p:h')

describe('git diff rendering', function()
  it('correctly processes a simple deletion', function()
    local hunk_lines = {
      '@@ -1,2 +1,1 @@',
      'line1',
      '[-line2-]',
    }
    local buffer_lines = { 'line1' }

    local result = require('forgit.diff').test_hunk_render(hunk_lines, buffer_lines)
    print(vim.inspect(result))

    -- Verify hunk was parsed correctly
    assert.equals(1, result.hunk_data.old_start)
    assert.equals(2, result.hunk_data.old_count)
    assert.equals(1, result.hunk_data.new_start)
    assert.equals(1, result.hunk_data.new_count)

    -- Verify rendering
    assert.equals(1, result.render_count) -- One deletion rendered
    assert.equals(1, #result.extmarks) -- One extmark created
  end)
  it('correctly processes a simple addition', function()
    local hunk_lines = {
      '@@ -1,1 +1,2 @@',
      'line1',
      '{+line2+}',
    }
    local buffer_lines = { 'line1', 'line2' }

    local result = require('forgit.diff').test_hunk_render(hunk_lines, buffer_lines)

    -- Verify hunk was parsed correctly
    assert.equals(1, result.hunk_data.old_start)
    assert.equals(1, result.hunk_data.old_count)
    assert.equals(1, result.hunk_data.new_start)
    assert.equals(2, result.hunk_data.new_count)

    -- Verify rendering
    assert.equals(1, result.render_count) -- One addition rendered
    assert.equals(1, #result.extmarks) -- One extmark created
  end)

  it('correctly processes a simple modification', function()
    local hunk_lines = {
      '@@ -1,2 +1,2 @@',
      'line1',
      '[-line2-]',
      '{+line3+}',
    }
    local buffer_lines = { 'line1', 'line3' }

    local result = require('forgit.diff').test_hunk_render(hunk_lines, buffer_lines)

    -- Verify hunk was parsed correctly
    assert.equals(1, result.hunk_data.old_start)
    assert.equals(2, result.hunk_data.old_count)
    assert.equals(1, result.hunk_data.new_start)
    assert.equals(2, result.hunk_data.new_count)

    -- Verify rendering
    assert.equals(2, result.render_count) -- One deletion and one addition rendered
    assert.equals(2, #result.extmarks) -- Two extmarks created
  end)
  it('correctly processes a simple inline modification', function()
    local hunk_lines = {
      '@@ -1,2 +1,2 @@',
      'line1',
      '[-line2-]{+line3+}',
    }
    local buffer_lines = { 'line1', 'line3' }

    local result = require('forgit.diff').test_hunk_render(hunk_lines, buffer_lines)

    -- Verify hunk was parsed correctly
    assert.equals(1, result.hunk_data.old_start)
    assert.equals(2, result.hunk_data.old_count)
    assert.equals(1, result.hunk_data.new_start)
    assert.equals(2, result.hunk_data.new_count)

    -- Verify rendering
    assert.equals(1, result.render_count) -- One deletion and one addition rendered
    assert.equals(2, #result.extmarks) -- Two extmarks created
  end)

  it('correctly processes a complex hunk', function()
    local hunk_lines = {
      '@@ -1,4 +1,4 @@',
      'line1',
      '[-line2-]',
      '{+line3+}',
      'line4',
    }
    local buffer_lines = { 'line1', 'line3', 'line4' }

    local result = require('forgit.diff').test_hunk_render(hunk_lines, buffer_lines)

    -- Verify hunk was parsed correctly
    assert.equals(1, result.hunk_data.old_start)
    assert.equals(4, result.hunk_data.old_count)
    assert.equals(1, result.hunk_data.new_start)
    assert.equals(4, result.hunk_data.new_count)

    -- Verify rendering
    assert.equals(2, result.render_count) -- One deletion and one addition rendered
    assert.equals(2, #result.extmarks) -- Two extmarks created
  end)

  it('correctly processes a hunk with no changes', function()
    local hunk_lines = {
      '@@ -1,2 +1,2 @@',
      'line1',
      'line2',
    }
    local buffer_lines = { 'line1', 'line2' }

    local result = require('forgit.diff').test_hunk_render(hunk_lines, buffer_lines)

    -- Verify hunk was parsed correctly
    assert.equals(1, result.hunk_data.old_start)
    assert.equals(2, result.hunk_data.old_count)
    assert.equals(1, result.hunk_data.new_start)
    assert.equals(2, result.hunk_data.new_count)

    -- Verify rendering
    assert.equals(0, result.render_count) -- No changes rendered
    assert.equals(0, #result.extmarks) -- No extmarks created
  end)
end)
