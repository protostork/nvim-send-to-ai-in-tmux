local M = {}

--- Check if running inside tmux
--- @return boolean True if in tmux session
function M.is_in_tmux()
  return vim.env.TMUX ~= nil
end

--- Get current tmux session name
--- @return string|nil Session name or nil if not in tmux
--- @return string|nil Error message
local function get_current_session()
  if not M.is_in_tmux() then
    return nil, "Not in tmux session"
  end

  local ok, result = pcall(vim.fn.systemlist, 'tmux display-message -p "#{session_name}"')
  if not ok or not result or #result == 0 or result[1] == '' then
    return nil, "Failed to get tmux session name"
  end

  return result[1], nil
end

--- List all tmux panes with their process information
--- @return table|nil Array of pane info {session, pane_id, command, title}
--- @return string|nil Error message
local function list_all_panes(config)
  if not M.is_in_tmux() then
    return nil, "Not in tmux session"
  end

  local search_all_windows = " -a "
  if config.prefer_window == true then
    search_all_windows = ""
  end

  local ok, panes = pcall(vim.fn.systemlist,
    'tmux list-panes ' .. search_all_windows .. '-F "#{session_name}:#{pane_id}:#{pane_current_command}:#{pane_title}"')

  if not ok or not panes or #panes == 0 then
    return nil, "Failed to query tmux panes"
  end

  -- Parse pane information
  local pane_list = {}
  for _, pane_info in ipairs(panes) do
    -- Format: session_name:pane_id:command:title
    local session, pane_id, command, title = pane_info:match("^([^:]+):([^:]+):([^:]*):(.*)$")
    if session and pane_id and command then
      table.insert(pane_list, {
        session = session,
        pane_id = pane_id,
        command = command,
        title = title or '',
      })
    end
  end

  return pane_list, nil
end

--- Resolve the actual binary names that tmux might report for AI processes.
--- Claude Code installs as a symlink (e.g., claude -> versions/2.1.42),
--- so tmux reports the version number as pane_current_command instead of "claude".
--- @param ai_processes string[] Configured AI process names
--- @return string[] Extended list including resolved binary names
local function resolve_ai_binary_names(ai_processes)
  local names = {}
  local seen = {}

  for _, name in ipairs(ai_processes) do
    local lower = name:lower()
    if not seen[lower] then
      seen[lower] = true
      table.insert(names, name)
    end

    -- Try to resolve the actual binary name via which + readlink
    local which_result = vim.fn.system('which ' .. vim.fn.shellescape(name) .. ' 2>/dev/null')
    local bin_path = vim.trim(which_result)
    if vim.v.shell_error == 0 and bin_path ~= '' then
      -- Follow symlinks to find the real binary
      local readlink_result = vim.fn.system('readlink ' .. vim.fn.shellescape(bin_path) .. ' 2>/dev/null')
      local real_path = vim.trim(readlink_result)
      if vim.v.shell_error == 0 and real_path ~= '' then
        -- Extract the basename of the resolved path (e.g., "2.1.42" from ".../versions/2.1.42")
        local resolved_name = real_path:match("([^/]+)$")
        if resolved_name then
          local resolved_lower = resolved_name:lower()
          if not seen[resolved_lower] then
            seen[resolved_lower] = true
            table.insert(names, resolved_name)
          end
        end
      end
    end
  end

  return names
end

--- Check if a pane matches any AI process name
--- @param pane table Pane info with command and title fields
--- @param ai_names string[] AI process names to match against
--- @return boolean
local function pane_matches_ai(pane, ai_names)
  local cmd_lower = pane.command:lower()
  local title_lower = pane.title:lower()

  for _, ai_name in ipairs(ai_names) do
    local pattern = ai_name:lower()
    if cmd_lower:find(pattern, 1, true) or title_lower:find(pattern, 1, true) then
      return true
    end
  end

  return false
end

--- Find AI pane based on process names in config
--- @param config table Configuration with ai_processes list
--- @return string|nil Pane ID or nil if not found
--- @return string|nil Error message
function M.find_ai_pane(config)
  if not M.is_in_tmux() then
    return nil, "Not in tmux session"
  end

  -- Get current session if prefer_session is enabled
  local current_session = nil
  if config.prefer_session then
    current_session, _ = get_current_session()
  end

  -- List all panes
  local panes, err = list_all_panes(config)
  if not panes then
    return nil, err or "Failed to list tmux panes"
  end

  -- Resolve AI binary names (handles symlinked binaries like claude -> 2.1.42)
  local ai_names = resolve_ai_binary_names(config.ai_processes)

  -- Find AI panes (substring match on command and title, case-insensitive)
  local ai_panes = {}
  for _, pane in ipairs(panes) do
    if pane_matches_ai(pane, ai_names) then
      table.insert(ai_panes, pane)
    end
  end

  if #ai_panes == 0 then
    return nil, "No AI panes found"
  end

  -- Prefer current session if enabled
  if current_session and config.prefer_session then
    for _, pane in ipairs(ai_panes) do
      if pane.session == current_session then
        return pane.pane_id, nil
      end
    end
  end

  -- Return first match
  local selected = ai_panes[1]

  -- Notify if multiple panes found
  if #ai_panes > 1 then
    vim.notify(
      string.format("Multiple AI panes found. Using %s (%s)", selected.pane_id, selected.command),
      vim.log.levels.INFO
    )
  end

  return selected.pane_id, nil
end

--- Escape text for tmux literal mode
--- @param text string Text to escape
--- @return string Escaped text
local function escape_for_tmux(text)
  -- In literal mode (-l), only backslashes need escaping
  return text:gsub([[\]], [[\\]])
end

--- Send text to tmux pane with literal mode (secure against shell injection)
--- @param pane_id string Tmux pane ID (e.g., "%2")
--- @param text string Text to send
--- @return boolean success
--- @return string|nil error Error message if failed
function M.send_to_pane(pane_id, text)
  if not M.is_in_tmux() then
    return false, "Not in tmux session"
  end

  -- Escape text for tmux literal mode
  local escaped = escape_for_tmux(text)

  -- Append a trailing newline so the cursor lands on a fresh line for the user to type
  escaped = escaped .. '\n'

  -- Send text with -l flag (literal mode - prevents shell interpretation)
  local send_cmd = string.format('tmux send-keys -t "%s" -l %s', pane_id, vim.fn.shellescape(escaped))
  local ok, result = pcall(vim.fn.system, send_cmd)

  if not ok or vim.v.shell_error ~= 0 then
    return false, string.format("Tmux send-keys failed: %s", result or "unknown error")
  end

  -- Switch focus to the AI pane
  local focus_cmd = string.format('tmux select-pane -t "%s"', pane_id)
  pcall(vim.fn.system, focus_cmd)

  return true, nil
end

return M