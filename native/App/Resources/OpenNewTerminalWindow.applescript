-- Base64 path tokens arrive as Apple event data. The command sent through the
-- Terminal PTY contains only printable ASCII, even for paths with control bytes.
on openFolders(folderTokens)
    -- Appending a sentinel before command substitution preserves trailing
    -- newlines in the decoded path. Only the fresh bash process sees the path.
    set shellBody to "folder=$(printf '%s' \"$1\" | /usr/bin/base64 -D && printf '.'); decodeStatus=$?; [ \"$decodeStatus\" -eq 0 ] || exit \"$decodeStatus\"; folder=${folder%.}; cd -- \"$folder\" || exit; "
    set shellBody to shellBody & "case \"${SHELL-}\" in /*) if [ -x \"$SHELL\" ] && [ ! -d \"$SHELL\" ]; then exec \"$SHELL\" -l; fi ;; esac; exec /bin/zsh -l"
    repeat with tokenIndex from 1 to count folderTokens
        set folderToken to item tokenIndex of folderTokens
        set terminalCommand to "exec /bin/bash -c " & quoted form of shellBody & " -- " & quoted form of (folderToken as text)
        tell application id "com.apple.Terminal"
            -- With no "in" target, Terminal creates a new window.
            do script terminalCommand
        end tell
    end repeat
    tell application id "com.apple.Terminal" to activate
end openFolders
