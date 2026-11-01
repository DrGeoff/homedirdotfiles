# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# ble.sh  -- load now and defer attach to the first prompt (ble.sh's own
# array-safe, $?-preserving deferral); keeps load+attach intent in one place.
[[ $- == *i* ]] && source ~/.local/share/blesh/ble.sh --attach=prompt

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
    # Snippets are flat files; source each top-level file in ~/.bashrc.d.
    # Subdirectories (e.g. tests/) are intentionally NOT sourced.
    for bashrc_entry in ~/.bashrc.d/*; do
        [ -f "$bashrc_entry" ] && . "$bashrc_entry"
    done
fi
unset bashrc_entry

# opencode
export PATH=/home/geoff/.opencode/bin:$PATH
. "$HOME/.cargo/env"

# Snippets above prepend unconditionally, so nested shells pile up duplicates.
# Drop repeats, keeping each entry's first (i.e. winning) position.
PATH="$(printf %s "$PATH" | awk -v RS=: -v ORS=: '!seen[$0]++' | sed 's/:$//')"
