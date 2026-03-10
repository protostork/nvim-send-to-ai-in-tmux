local M = {}

--- Health check for send-to-ai plugin
function M.check()
  vim.health.start('send-to-ai')

  local config = require('send-to-ai.config')
  local tmux = require('send-to-ai.tmux')
  local clipboard = require('send-to-ai.clipboard')
  local cfg = config.get()

  -- Check tmux installation
  vim.health.info('Tmux')
  if vim.fn.executable('tmux') == 1 then
    -- Get tmux version
    local ok, version = pcall(vim.fn.systemlist, 'tmux -V')
    if ok and version and #version > 0 then
      vim.health.ok(string.format('tmux is installed (%s)', version[1]))

      -- Check tmux version (warn if < 2.0)
      local version_num = version[1]:match('tmux (%d+%.%d+)')
      if version_num then
        local major, minor = version_num:match('(%d+)%.(%d+)')
        if major and tonumber(major) < 2 then
          vim.health.warn(
            string.format('tmux version is old (%s). Recommended >= 2.0', version_num),
            { 'Upgrade tmux: brew upgrade tmux (macOS) or apt upgrade tmux (Linux)' }
          )
        end
      end
    else
      vim.health.ok('tmux is installed')
    end

    -- Check if in tmux session
    if tmux.is_in_tmux() then
      local session_ok, session = pcall(vim.fn.systemlist, 'tmux display-message -p "#{session_name}"')
      if session_ok and session and #session > 0 then
        vim.health.ok(string.format("Running inside tmux session '%s'", session[1]))
      else
        vim.health.ok('Running inside tmux session')
      end
    else
      vim.health.warn(
        'Not in a tmux session',
        { 'Start tmux to enable AI pane detection', 'Clipboard fallback will be used' }
      )
    end
  else
    vim.health.error(
      'tmux is not installed',
      {
        'Install tmux:',
        '  macOS: brew install tmux',
        '  Ubuntu/Debian: sudo apt install tmux',
        '  Fedora: sudo dnf install tmux',
        'Without tmux, only clipboard mode is available'
      }
    )
  end

  -- Check clipboard support
  vim.health.info('Clipboard')
  local clip_cmd = clipboard.detect_clipboard_command()
  if clip_cmd then
    local clip_names = {
      pbcopy = 'pbcopy (macOS)',
      ['clip.exe'] = 'clip.exe (WSL)',
      ['wl-copy'] = 'wl-copy (Wayland)',
      xclip = 'xclip (X11)',
      xsel = 'xsel (X11)',
    }
    vim.health.ok(string.format('Clipboard support: %s', clip_names[clip_cmd] or clip_cmd))
  else
    vim.health.warn(
      'No clipboard command found',
      {
        'Install a clipboard tool:',
        '  macOS: pbcopy (built-in)',
        '  Linux X11: sudo apt install xclip',
        '  Linux Wayland: sudo apt install wl-clipboard',
        '  WSL: clip.exe (built-in)',
        'Without clipboard, you need tmux for the plugin to work'
      }
    )
  end

  -- Check for AI panes (only if in tmux)
  if tmux.is_in_tmux() then
    vim.health.info('AI Panes')
    local pane_id, err = tmux.find_ai_pane(cfg)

    if pane_id then
      -- Get pane info
      local pane_ok, pane_info = pcall(vim.fn.systemlist,
        string.format('tmux list-panes -a -F "#{pane_id}:#{session_name}:#{pane_current_command}" | grep "^%s:"', pane_id))

      if pane_ok and pane_info and #pane_info > 0 then
        local _, session, command = pane_info[1]:match('^([^:]+):([^:]+):(.+)$')
        if session and command then
          vim.health.ok(string.format("AI pane detected: %s (%s) in session '%s'", pane_id, command, session))
        else
          vim.health.ok(string.format('AI pane detected: %s', pane_id))
        end
      else
        vim.health.ok(string.format('AI pane detected: %s', pane_id))
      end
    else
      vim.health.warn(
        string.format('No AI panes found: %s', err or 'unknown reason'),
        {
          'Start an AI tool in a tmux pane:',
          '  claude, codex, opencode, etc.',
          string.format('Configured AI processes: %s', table.concat(cfg.ai_processes, ', ')),
          'Or customize ai_processes in setup()'
        }
      )
    end
  end

  -- Check configuration
  vim.health.info('Configuration')
  vim.health.ok(string.format('path_style: %s', cfg.path_style))
  vim.health.ok(string.format('ai_processes: %s', table.concat(cfg.ai_processes, ', ')))
  vim.health.ok(string.format('max_selection_lines: %d', cfg.max_selection_lines))
  vim.health.ok(string.format('prefer_session: %s', tostring(cfg.prefer_session)))
  vim.health.ok(string.format('prefer_window: %s', tostring(cfg.prefer_window)))
  vim.health.ok(string.format('fallback_clipboard: %s', tostring(cfg.fallback_clipboard)))
end

return M