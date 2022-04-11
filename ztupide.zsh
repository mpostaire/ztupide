#!/usr/bin/env zsh

# status codes: s = success, f failure | types: p = plugin, t = theme
_ztupide_load() {
    [ -d "${ZTUPIDE_PLUGIN_PATH}" ] || mkdir "${ZTUPIDE_PLUGIN_PATH}"

    local plugin_name="${1:t}"
    local plugin_path="${ZTUPIDE_PLUGIN_PATH}"/"${plugin_name}"
    [[ "${1}" =~ .+"/".+ && ! -d "${plugin_path}" ]] && git -C "${ZTUPIDE_PLUGIN_PATH}" clone https://github.com/"${1:t2}" --quiet

    local plugin_file=("${plugin_path}"/*.plugin.zsh(NY1)) # match first .plugin.zsh found, prevents multiple .plugin.zsh
    local theme_file=("${plugin_path}"/*.zsh-theme(NY1)) # match first .zsh-theme found, prevents multiple .zsh-theme
    
    # zcompile all .zsh/.zsh-theme files
    for f in "${plugin_path}"/**/*.{zsh,zsh-theme}(N); do
        [[ ! -z "${force}" || ( ! "${f}".zwc -nt "${f}" && -r "${f}" && -w "${f:h}" ) ]] && zcompile $f
    done
    
    local callbacks="${(@j/:/)@:2}"
    if [[ -d "${plugin_path}" && "${#plugin_file}" -eq 1 ]]; then
        print "s:p:${1}:${callbacks:+${callbacks}:}${plugin_file[1]}"
    elif [[ -d "${plugin_path}" && -z "${_ztupide_loaded_theme}" && "${#theme_file}" -eq 1 ]]; then
        print "s:t:${1}:${callbacks:+${callbacks}:}${theme_file[1]}"
    elif [[ -d "${plugin_path}" && -n "${_ztupide_loaded_theme}" && "${#theme_file}" -eq 1 ]]; then
        print "f:t:${1}:/"
    else
        [ -d "${plugin_path}"/.git ] && rm -rf "${plugin_path}"
        print "f:p:${1}:/"
    fi
}

_ztupide_remove() {
    [ -z "${1}" ] && print "plugin remove error: none specified" && return 1

    local plugin_name="${1:t}"
    local plugin_path="${ZTUPIDE_PLUGIN_PATH}"/"${plugin_name}"

    if [ -d "${plugin_path}" ]; then
        if [ -d "${plugin_path}"/.git ]; then
            rm -rf "${plugin_path}"
            print "plugin ${plugin_name} removed"
        else
            read "ans?${plugin_name} is a local plugin. Do you want to remove it (y/N)? "
            if [[ "${ans}" =~ ^[Yy]$ ]]; then
                rm -rf "${plugin_path}"
                print "plugin ${plugin_name} removed"
            fi
        fi
    else
        print "plugin remove error: ${plugin_name} plugin not found"
        return 1
    fi
}

_ztupide_update() {
    echo "checking ${1:t} for updates..."
    [ -z "$(git -C ${1} branch --list main)" ] && local branch="master" || local branch="main"
    git -C ${1} fetch origin "${branch}" --quiet
    local local=$(git -C ${1} rev-parse HEAD)
    local base=$(git -C ${1} rev-parse '@{u}')
    if [ "${local}" != "${base}" ]; then
        git -C ${1} reset --hard origin/"${branch}"
        git -C ${1} pull origin "${branch}" --quiet
        echo "${1:t} updated"
    fi
}

_ztupide_update_all() {
    _ztupide_update ${_ztupide_path:h}

    local plugin_path
    for plugin_path in "${ZTUPIDE_PLUGIN_PATH}"/*(/N); do
        if [ -d "${plugin_path}"/.git ]; then
            local plugin_file=("${plugin_path}"/*.plugin.zsh(NY1))
            if [ "${#plugin_file}" -eq 1 ]; then
                _ztupide_update ${plugin_path}
            fi
        fi
    done
    
    print "${EPOCHSECONDS}" > ~/.zsh/ztupide/ztupide_last_update
}

_ztupide_autoupdate() {
    if [ ! -z ${ZTUPIDE_AUTOUPDATE} ]; then
        if [ -f ~/.zsh/ztupide/ztupide_last_update ]; then
            local delta=$(cat ~/.zsh/ztupide/ztupide_last_update)
            (( delta = ${EPOCHSECONDS} - ${delta} ))
            [ ${delta} -gt ${ZTUPIDE_AUTOUPDATE} ] && _ztupide_update_all
        else
            _ztupide_update_all
        fi
    fi
}

_ztupide_load_async_handler() {
    if read -r -u ${1} line; then
        local plugin_path=/${line##*:/}
        local meta=(${(@s/:/)${${line%"${plugin_path}"}:0:-1}})

        if [[ "${meta[1]}" = "s" ]]; then
            _ztupide_to_source["${meta[3]}"]="${meta[2]}:${plugin_path}"

            for plugin in ${_ztupide_to_load}; do
                if [ -z "${_ztupide_to_source["${plugin}"]}" ]; then
                    return
                elif [ "${_ztupide_to_source["${plugin}"]}" = "f" ]; then
                    _ztupide_to_load=(${_ztupide_to_load:1})
                else
                    if [[ "${${_ztupide_to_source["${plugin}"]}[1]}" = "t" ]]; then
                        if [[ -z "${_ztupide_loaded_theme}" ]]; then
                            _ztupide_loaded_theme="${plugin}"
                        else
                            print "theme load error: "${plugin}" -> the following theme is already in use: ${_ztupide_loaded_theme}"
                            continue
                        fi
                    fi
                    _ztupide_to_load=(${_ztupide_to_load:1})
                    builtin source "${_ztupide_to_source["${plugin}"]:2}" > /dev/null 2> /dev/null 

                    for c in ${(s/:/)meta[4]}; do eval "${c}"; done # eval callbacks
                fi
            done
        else
            _ztupide_to_source["${meta[3]}"]="f"
            if [[ "${meta[2]}" = "t" ]]; then
                print "theme load error: "${meta[3]}" -> the following theme is already in use: ${_ztupide_loaded_theme}"
            else
                print "plugin load error: "${meta[3]}" is not a valid plugin"
            fi
        fi
    fi
    
    # close FD
    exec {1}<&-
    # remove handler
    zle -F ${1}
}

_ztupide_load_sync() {
    local ret=$(_ztupide_load ${@})
    local plugin_path=/${ret##*:/}
    local meta=(${(@s/:/)${${ret%"${plugin_path}"}:0:-1}})

    if [[ "${meta[1]}" = "s" ]]; then
        [[ "${meta[2]}" = "t" ]] && _ztupide_loaded_theme="${meta[3]}"
        builtin source "${plugin_path}" > /dev/null 2> /dev/null
        for c in ${(s/:/)meta[4]}; do eval "${c}"; done # eval callbacks
    elif [[ "${meta[2]}" = "t" ]]; then
        print "theme load error: "${meta[3]}" -> the following theme is already in use: ${_ztupide_loaded_theme}"
    else
        print "plugin load error: "${meta[3]}" is not a valid plugin"
    fi
}

_ztupide_load_async() {
    # create async_fd
    local async_fd
    exec {async_fd}< <(_ztupide_load ${@})

    # needed to fix ctrl+c not working in some cases
    command true

    # zle -F installs input handler on given FD
    zle -F ${async_fd} _ztupide_load_async_handler
}

_ztupide_init() {
    _ztupide_path=${1:a}
    typeset -g _ztupide_loaded_theme

    ZTUPIDE_PLUGIN_PATH=${ZTUPIDE_PLUGIN_PATH:-~/.zsh/plugins}
    # zcompile this file
    [[ ! "${_ztupide_path}".zwc -nt "${_ztupide_path}" && -r "${_ztupide_path}" && -w "${_ztupide_path:h}" ]] && zcompile ${_ztupide_path}

    zmodload zsh/datetime
    _ztupide_autoupdate

    _ztupide_to_load=()
    typeset -gA _ztupide_to_source

    # add completion function to fpath
    fpath+=("${_ztupide_path:h}")
}

_ztupide_help() {
    print "Usage : ztupide OPTION [--async] [PLUGIN]

Options:
help\t\tshows this message
load\t\tload PLUGIN (asynchronously if --async used)
remove\t\tremove PLUGIN
update\t\tupdate ztupide and all plugins"
}

ztupide() {
    case "${1}" in
    load)
        if [ "${2}" = "--async" ]; then
            [ -z "${3}" ] && print "plugin load error: none specified" && return 1
            _ztupide_to_load+="${3}"
            _ztupide_load_async ${@:3}
        else
            [ -z "${2}" ] && print "plugin load error: none specified" && return 1
            _ztupide_load_sync "${@:2}"
        fi
        ;;
    remove)
        _ztupide_remove "${2}"
        ;;
    update)
        _ztupide_update_all
        ;;
    help)
        _ztupide_help
        ;;
    *)
        _ztupide_help
        return 1
        ;;
    esac
}

_ztupide_init ${0}
