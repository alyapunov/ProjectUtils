#!/bin/bash
# BSD 2-Clause License
#
# Copyright (c) 2022, Aleksandr Lyapunov
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

script_dir=$(realpath "${BASH_SOURCE:-$0}")
bin_dir=$(dirname "$script_dir")

is_uninstall=false
if [[ "$1" == "-u" ]] || [[ "$1" == "--uninstall" ]]; then
    is_uninstall=true
fi

get_binding_name() {
    local binding="$1"
    gsettings get "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$binding" name
}

set_binding_name() {
    local binding="$1"
    local name="$2"
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$binding" name "$name"
}

set_binding_props() {
    local binding="$1"
    local command="$2"
    local shortcut="$3"
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$binding" command "$command"
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$binding" binding "$shortcut"
}

drop_binding_props() {
    local binding="$1"
    gsettings reset-recursively "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$binding"
}

find_binding_by_name() {
    local name="$1"
    all_bindings=`gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings`
    if [[ $all_bindings =~ ^@[a-z]+[[:space:]]*\[\]$ ]]; then
        return 0
    fi
    if ! [[ $all_bindings =~ ^\[(.*)\]$ ]]; then
        echo "all bindings parse failed (1)!"
        exit 1
    fi
    bindings_scan=${BASH_REMATCH[1]}
    pattern1="^'([^']*)',[[:space:]]*('.*')$"
    pattern2="^'([^']*)'$"
    while [[ "$bindings_scan" =~ $pattern1 ]]; do
        local binding=${BASH_REMATCH[1]}
        local binding_name=`get_binding_name "$binding"`
        if [[ "$binding_name" == "'$name'" ]]; then
            echo $binding
            return 0
        fi
        bindings_scan=${BASH_REMATCH[2]}
    done
    if ! [[ "$bindings_scan" =~ $pattern2 ]]; then
        echo "all bindings parse failed (2)!"
        exit 1
    fi
    local binding=${BASH_REMATCH[1]}
    local binding_name=`get_binding_name "$binding"`
    if [[ "$binding_name" == "'$name'" ]]; then
        echo $binding
        return 0
    fi
}

get_binding_by_name() {
    local name="$1"
    local binding=`find_binding_by_name "$name"`
    if [[ -n "$binding" ]]; then
        echo "$binding"
        return 0
    fi

    all_bindings=`gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings`
    if [[ $all_bindings =~ ^@[a-z]+[[:space:]]*\[\]$ ]]; then
        all_bindings='[]'
    fi

    local prev_i="?"
    for i in {0..49}; do
        local test="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$i/"
        local prev_test="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom$prev_i/"
        local pattern1="'$test'"
        local pattern2="^\[(.+)\]$"
        local pattern3="^(.*')$prev_test('.*)$"
        if ! [[ $all_bindings =~ $pattern1 ]]; then
            if [[ "$all_bindings" == "[]" ]]; then
                all_bindings="['$test']"
            elif [[ $prev_i == "?" ]]; then
                if [[ "$all_bindings" =~ $pattern2 ]]; then
                    all_bindings="['$test', ${BASH_REMATCH[1]}]"
                else
                    echo "all bindings parse failed (3)!"
                    exit 1
                fi
            elif [[ "$all_bindings" =~ $pattern3 ]]; then
                all_bindings="${BASH_REMATCH[1]}$prev_test', '$test${BASH_REMATCH[2]}"
            else
                echo "all bindings parse failed (4)!"
                exit 1
            fi
            gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$all_bindings"
            set_binding_name "$test" "$name"
            echo "$test"
            return 0
        fi
        prev_i=$i
    done
}

install_binding() {
    local name="$1"
    local command="$2"
    local shortcut="$3"
    local binding=`get_binding_by_name "$name"`
    set_binding_props "$binding" "$command" "$shortcut"
}

uninstall_binding() {
    local name="$1"
    local binding=`find_binding_by_name "$name"`
    if [[ -z "$binding" ]]; then
        return 0
    fi
    all_bindings=`gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings`

    pattern1="^(.*)'$binding',[[:space:]]*('.*)$"
    pattern2="^(.*'),[[:space:]]*'$binding'(.*)$"
    pattern3="^\['$binding'\]$"
    if [[ "$all_bindings" =~ $pattern1 ]]; then
        all_bindings="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    elif [[ "$all_bindings" =~ $pattern2 ]]; then
        all_bindings="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    elif [[ "$all_bindings" =~ $pattern3 ]]; then
        all_bindings="[]"
    else
        echo "all bindings parse failed (5)!"
        exit 1
    fi
    drop_binding_props "$binding"
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$all_bindings"
}

if [[ $is_uninstall == false ]]; then
    ln -s "$bin_dir/replay.sh" ~/bin/replay.sh
    install_binding 'replay_next' "$bin_dir/replay_next.sh" '<Control><Shift>F9'
else
    rm ~/bin/replay.sh
    uninstall_binding 'replay_next'
fi
