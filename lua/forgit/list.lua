local function git_cmds()
  local cmdlst = require('forgit.commands').cmds()

  local data = {}
  for k, v in pairs(cmdlst) do
    table.insert(data, { k, v })
  end

  vim.list_extend(data, require('forgit').cmds)
  local view_data = {}
  for _, v in ipairs(data) do
    table.insert(view_data, { text = v[1] .. '\t| ' .. v [2], cmd = v[1] })
  end
  if vim.fn.empty(_FORGIT_CFG.cmds_list) == 0 then
    vim.list.extend(view_data, _FORGIT_CFG.cmds_list)
  end

  local lsview = require('guihua.listview')
  local win = lsview:new({
    loc = 'top_center',
    border = 'single',
    prompt = true,
    enter = true,
    rect = { height = 20, width = 60 },
    data = view_data,
    on_confirm = function(item) vim.cmd(item.cmd) end,
  })
  -- one command to rule them all
end

vim.api.nvim_create_user_command('Forgit', 'lua require("forgit.list").git_cmds()', {force = false})

return {git_cmds = git_cmds}
