#!/usr/bin/env zsh

# TODO comments

_ztupide_source() {
    for f in ${1:h}/**/*.zsh; do
        [[ ! -z "${force}" || ( ! "${f}".zwc -nt "${f}" && -r "${f}" && -w "${f:h}" ) ]] && zcompile $f
    done
    builtin source "${1}"
}

_ztupide_load() {
    # TODO: support for .zsh-theme
    [ -d "${ZTUPIDE_PLUGIN_PATH}" ] || mkdir "${ZTUPIDE_PLUGIN_PATH}"

    local plugin_name="${1:t}"
    local plugin_path="${ZTUPIDE_PLUGIN_PATH}"/"${plugin_name}"
    [[ "${1}" =~ .+"/".+ && ! -d "${plugin_path}" ]] && git -C "${ZTUPIDE_PLUGIN_PATH}" clone https://github.com/"${1:t2}" --quiet

    
    local plugin_file=("${plugin_path}"/*.plugin.zsh(NY1)) # match first .plugin.zsh found, prevents multiple .plugin.zsh
    if [[ -d "${plugin_path}" && "${#plugin_file}" -eq 1 ]]; then
        echo "_load_success:${1}:${plugin_file[1]}:${2}"
    else
        rm -rf "${plugin_path}"
        echo "_load_fail:${1}"
    fi
}

_ztupide_remove() {
    [ -z "${1}" ] && echo "plugin remove error: none specified" && exit 1

    local plugin_name="${1:t}"
    local plugin_path="${ZTUPIDE_PLUGIN_PATH}"/"${plugin_name}"

    if [ -d "${plugin_path}" ]; then
        if [ -d "${plugin_path}"/.git ]; then
            rm -rf "${plugin_path}"
            echo "plugin ${plugin_name} removed"
        else
            read "ans?${plugin_name} is a local plugin. Do you want to remove it (y/N)? "
            if [[ "${ans}" =~ ^[Yy]$ ]]; then
                rm -rf "${plugin_path}"
                echo "plugin ${plugin_name} removed"
            fi
        fi
    else
        echo "plugin remove error: ${plugin_name} plugin not found"
        exit 1
    fi
}

_ztupide_update() {
    git -C ${_ztupide_path:h} fetch
    local local=$(git -C ${_ztupide_path:h} rev-parse HEAD)
    local base=$(git -C ${_ztupide_path:h} rev-parse '@{u}')
    if [ "${local}" != "${base}" ]; then
        echo "ztupide self updating..."
        git -C ${_ztupide_path:h} pull origin master --quiet
        echo "ztupide updated"
        # local self_updated=1
    fi

    echo "ztupide updating plugins..."
    local plugin_path
    for plugin_path in "${ZTUPIDE_PLUGIN_PATH}"/*(/N); do
        if [ -d "${plugin_path}"/.git ]; then
            local plugin_file=("${plugin_path}"/*.plugin.zsh(NY1))
            if [ "${#plugin_file}" -eq 1 ]; then
                git -C "${plugin_path}" pull origin master --quiet
                local plugin_name="${plugin_path:t}"
                echo "${plugin_name} plugin updated"
            fi
        fi
    done
    
    echo "plugins updated"
    echo "${EPOCHSECONDS}" > ~/.zsh/ztupide/ztupide_last_update

    # [ -z ${self_updated} ] || exec zsh
}

_ztupide_autoupdate() {
    if [ ! -z ${ZTUPIDE_AUTOUPDATE} ]; then
        if [ -f ~/.zsh/ztupide/ztupide_last_update ]; then
            local delta=$(cat ~/.zsh/ztupide/ztupide_last_update)
            (( delta = ${EPOCHSECONDS} - ${delta} ))
            [ ${delta} -gt ${ZTUPIDE_AUTOUPDATE} ] && _ztupide_update
        else
            _ztupide_update
        fi
    fi
}

_ztupide_load_async_handler() {
    if read -r -u "${1}" line && [[ "${line}" =~ "_load*" ]]; then
        # close FD
        exec {1}<&-
        # remove handler
        zle -F "${1}"

        if [[ "${line}" =~ "_load_success:*" ]]; then
            local ret=(${(@s/:/)line})
            _ztupide_to_source["${ret[2]}"]="${ret[3]}"

            for e in ${_ztupide_to_load}; do
                if [ -z "${_ztupide_to_source["${e}"]}" ]; then
                    return
                elif [ "${_ztupide_to_source["${e}"]}" = "_fail" ]; then
                    _ztupide_to_load=(${_ztupide_to_load:1})
                else
                    _ztupide_to_load=(${_ztupide_to_load:1})
                    _ztupide_source "${_ztupide_to_source["${e}"]}"
                    [ -z "${ret[4]}" ] || eval "${ret[4]}"
                fi
            done
        else
            _ztupide_to_source["${${(@s/:/)line}[2]}"]="_fail"
            echo "plugin load error: "${${(@s/:/)line}[2]}" is not a valid plugin"
        fi
    fi
}

_ztupide_load_sync() {
    local ret=$(_ztupide_load "${1}")
    if [[ "${ret}" =~ "_load_success:*" ]]; then
        ret=(${(@s/:/)ret})
        _ztupide_source "${ret[3]}"
        [ -z "${ret[4]}" ] || eval "${ret[4]}"
    else
        echo "plugin load error: "${${(@s/:/)ret}[2]}" is not a valid plugin"
    fi
}

_ztupide_load_async() {
    # create async_fd
    local async_fd
    exec {async_fd}< <(_ztupide_load ${@})

    # needed to fix ctrl+c not working in some cases
    command true

    # zle -F installs input handler on given FD
    zle -F "${async_fd}" _ztupide_load_async_handler
}

_ztupide_init() {
    _ztupide_path=${1:a}

    ZTUPIDE_PLUGIN_PATH=${ZTUPIDE_PLUGIN_PATH:-~/.zsh/plugins}
    # zcompile this file
    [[ ! "${_ztupide_path}".zwc -nt "${_ztupide_path}" && -r "${_ztupide_path}" && -w "${_ztupide_path:h}" ]] && zcompile ${_ztupide_path}

    zmodload zsh/datetime
    _ztupide_autoupdate

    _ztupide_to_load=()
    typeset -gA _ztupide_to_source

    compdef _ztupide ztupide
}

ztupide() {
    case "${1}" in
    load)
        [ -z "${2}" ] && echo "plugin load error: none specified" && exit 1
        if [ "${2}" = "--async" ]; then
            _ztupide_to_load+="${3}"
            _ztupide_load_async ${@:3}
        else
            _ztupide_load_sync "${2}"
        fi
        ;;
    remove)
        _ztupide_remove "${2}"
        ;;
    update)
        _ztupide_update
        ;;
    *)
        echo "Usage : ztupide OPTION [--async] [PLUGIN]
        
Options:
load\t\tload PLUGIN (asynchronously if --async used)
remove\t\tremove PLUGIN
update\t\tupdate ztupide and all plugins"
        ;;
    esac
}

# completion function
function _ztupide() {
    local line
    _arguments -C \
        '1: :((load\:"load plugin" remove\:"remove plugin" update\:"update ztupide and all plugins"))' \
        '*::arg:->args'

    local plugins=(${ZTUPIDE_PLUGIN_PATH}/*(N))
    for ((i = 1; i <= ${#plugins}; i++)); do
        plugins[${i}]=${plugins[${i}]:t}
    done

    case ${line[1]} in
        load)
            _arguments -C "1: :((--async\:'load plugin asynchronously' ${plugins}))" '*::arg:->args'
            case ${line[1]} in
                --async)
                    _arguments "1: :(${plugins})"
                    ;;
            esac
            ;;
        remove)
            _arguments "1: :(${plugins})"
            ;;
    esac;
}

_ztupide_init ${0}
