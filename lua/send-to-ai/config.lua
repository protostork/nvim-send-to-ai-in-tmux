local M = {}

-- Default configuration
local defaults = {
  ai_processes = { 'claude', 'codex', 'opencode' },
  prefer_session = true,
  prefer_window = false,
  fallback_clipboard = true,
  path_style = 'git_relative',
  path_style_fallback = 'filename_only',
  max_selection_lines = 10000,
  warn_selection_lines = 5000,
  cache_pane_detection = false,
}

-- Current configuration (starts as defaults)
local config = vim.deepcopy(defaults)

-- Valid values for validation
local valid_path_styles = { 'git_relative', 'cwd_relative', 'absolute' }
local valid_path_fallbacks = { 'filename_only', 'cwd_relative', 'absolute' }

--- Validates configuration values
--- @param user_config table User configuration
--- @return boolean success
--- @return string|nil error Error message if validation fails
local function validate_config(user_config)
  -- Validate path_style
  if user_config.path_style then
    local valid = false
    for _, style in ipairs(valid_path_styles) do
      if user_config.path_style == style then
        valid = true
        break
      end
    end
    if not valid then
      return false, string.format(
        "Invalid path_style '%s'. Must be one of: %s",
        user_config.path_style,
        table.concat(valid_path_styles, ', ')
      )
    end
  end

  -- Validate path_style_fallback
  if user_config.path_style_fallback then
    local valid = false
    for _, fallback in ipairs(valid_path_fallbacks) do
      if user_config.path_style_fallback == fallback then
        valid = true
        break
      end
    end
    if not valid then
      return false, string.format(
        "Invalid path_style_fallback '%s'. Must be one of: %s",
        user_config.path_style_fallback,
        table.concat(valid_path_fallbacks, ', ')
      )
    end
  end

  -- Validate ai_processes
  if user_config.ai_processes then
    if type(user_config.ai_processes) ~= 'table' then
      return false, "ai_processes must be a table (array of strings)"
    end
    if #user_config.ai_processes == 0 then
      return false, "ai_processes cannot be empty. Provide at least one AI process name."
    end
    for i, process in ipairs(user_config.ai_processes) do
      if type(process) ~= 'string' then
        return false, string.format("ai_processes[%d] must be a string, got %s", i, type(process))
      end
    end
  end

  -- Validate max_selection_lines
  if user_config.max_selection_lines then
    if type(user_config.max_selection_lines) ~= 'number' or user_config.max_selection_lines <= 0 then
      return false, "max_selection_lines must be a positive number"
    end
  end

  -- Validate warn_selection_lines
  if user_config.warn_selection_lines then
    if type(user_config.warn_selection_lines) ~= 'number' or user_config.warn_selection_lines < 0 then
      return false, "warn_selection_lines must be a non-negative number"
    end
  end

  return true, nil
end

--- Setup configuration with user overrides
--- @param user_config table|nil User configuration to merge with defaults
function M.setup(user_config)
  user_config = user_config or {}

  -- Validate before merging
  local valid, err = validate_config(user_config)
  if not valid then
    vim.notify(
      string.format("[send-to-ai] Configuration error: %s", err),
      vim.log.levels.ERROR
    )
    return
  end

  -- Deep merge user config into defaults
  config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), user_config)
end

--- Get current configuration
--- @return table Current configuration
function M.get()
  return config
end

return M