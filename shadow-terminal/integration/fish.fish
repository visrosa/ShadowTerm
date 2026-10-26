# Loaded by one launched fish process through --init-command. These definitions
# are deliberately not installed or saved into the user's configuration.
status is-interactive; or return
set -q SHADOW_TERM_HELPER SHADOW_TERM_SESSION SHADOW_TERM_TOKEN; or return

# Keep prompt drawing local to this shell. The original functions are retained
# for native editing; no escape-code erasure or command-output filtering occurs.
set --global __vcom_prompt_hidden 1
functions --copy fish_prompt __vcom_saved_prompt
if functions --query fish_right_prompt
    functions --copy fish_right_prompt __vcom_saved_right_prompt
end

function __vcom_restore_status
    return $argv[1]
end

function fish_prompt
    set --local previous_status $status
    if set --query __vcom_prompt_hidden
        return $previous_status
    end
    __vcom_restore_status $previous_status
    __vcom_saved_prompt
end

function fish_right_prompt
    set --local previous_status $status
    if set --query __vcom_prompt_hidden
        return $previous_status
    end
    if functions --query __vcom_saved_right_prompt
        __vcom_restore_status $previous_status
        __vcom_saved_right_prompt
    end
end

function __vcom_presentation
    set --local previous_status $status
    if command "$SHADOW_TERM_HELPER" presentation 2>/dev/null
        set --global __vcom_prompt_hidden 1
    else
        set --erase __vcom_prompt_hidden
    end
    commandline --function repaint
    return $previous_status
end

function __vcom_postexec --on-event fish_postexec
    # Capture both statuses before any provider/helper commands run. Keep this
    # result across prompt repaints, completion queries and presentation toggles.
    set --local previous $status $pipestatus
    set --global __vcom_result $previous[1]
    set --global __vcom_pipeline $previous[2..]
    set --global __vcom_duration "$CMD_DURATION"
    return $previous[1]
end

function __vcom_prompt --on-event fish_prompt
    set --local previous_status $status
    set --local has_result 0
    set --local result 0
    set --local pipeline 0
    set --local duration 0
    if set --query __vcom_result
        set has_result 1
        set result $__vcom_result
        set pipeline (string join , -- $__vcom_pipeline)
        set duration $__vcom_duration
    end
    set --local remote 0
    if test -n "$SSH_CONNECTION"; or test -n "$SSH_TTY"
        set remote 1
    end
    command "$SHADOW_TERM_HELPER" context "$has_result" "$result" "$pipeline" "$duration" \
        "$VIRTUAL_ENV" "$CONDA_DEFAULT_ENV" "$remote" "$(count (jobs --group))" "$USER" "$hostname" 2>/dev/null
    command "$SHADOW_TERM_HELPER" metadata "$(abbr --show)" "$(complete)" "$(string join : -- $fish_complete_path)" "$(string join : -- $fish_function_path)" 2>/dev/null
    # Transfer bounded complete history entries in the readiness handshake.
    # NUL framing preserves multiline source; the response selects presentation
    # without another helper running after the host has announced readiness.
    if builtin history search --null --max=200 | command "$SHADOW_TERM_HELPER" ready 2>/dev/null
        set --global __vcom_prompt_hidden 1
    else
        # Native editing and a disconnected host both need a usable prompt.
        set --erase __vcom_prompt_hidden
    end
    return $previous_status
end

function __vcom_preexec --on-event fish_preexec
    set --local previous_status $status
    command "$SHADOW_TERM_HELPER" busy 2>/dev/null
    return $previous_status
end

function __vcom_submit
    set --local previous_status $status
    # Native editing remains available. Never append a GUI command to an
    # unfinished native buffer or silently discard what was typed there.
    # commandline appends one newline even for an empty buffer. NUL-aware
    # collection preserves any additional newlines that belong to the buffer.
    set --local native (commandline --current-buffer | string split0)
    if test "$native" != \n
        command "$SHADOW_TERM_HELPER" rejected 'Finish or clear the native fish buffer first'
        return $previous_status
    end
    set --local source (command "$SHADOW_TERM_HELPER" take | string split0)
    if test $pipestatus[1] -ne 0
        return $previous_status
    end
    commandline --replace -- "$source"
    commandline --is-valid
    set --local validity $status
    if test $validity -ne 0
        commandline --replace ''
        if test $validity -eq 2
            command "$SHADOW_TERM_HELPER" rejected 'Incomplete fish command; add another line'
        else
            command "$SHADOW_TERM_HELPER" rejected 'Invalid fish syntax; draft retained'
        end
        return $previous_status
    end
    if command "$SHADOW_TERM_HELPER" accepted
        commandline --function execute
    else
        # The request may have expired while the shell was unavailable.
        commandline --replace ''
    end
    return $previous_status
end

# This private input-function sequence carries no source or styling bytes.
bind --mode default alt-ctrl-o __vcom_submit
bind --mode insert alt-ctrl-o __vcom_submit
bind --mode default alt-ctrl-p __vcom_presentation
bind --mode insert alt-ctrl-p __vcom_presentation
