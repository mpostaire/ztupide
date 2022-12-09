#!/usr/bin/env zsh

# credit: https://github.com/mattmc3/zsh_unplugged

_ztupide_zcompile() {
    local f
    for f in ${1}/**/*.zsh{,-theme}(N); do
        [[ ! "${f}".zwc -nt "${f}" && -r "${f}" && -w "${f:h}" ]] && zcompile $f
    done
}

# args: repo, callback, async
_ztupide_load() {
    local repo plugdir initfile

    repo=${2}
    plugdir=${ZTUPIDE_PLUGIN_PATH}/${repo:t}
    initfile=${plugdir}/${repo:t}.plugin.zsh
    if [[ "${repo}" =~ .+"/".+ && ! -d ${plugdir} ]]; then
        print "Installing ${repo}..."
        git clone -q --depth 1 --recursive --shallow-submodules https://github.com/${repo} ${plugdir}
        _ztupide_zcompile ${plugdir}
    fi
    if [[ ! -e ${initfile} ]]; then
        local -a initfiles=(${plugdir}/*.plugin.{z,}sh(N) ${plugdir}/*.{z,}sh{-theme,}(N))
        (( ${#initfiles} )) || { print "Plugin load error: \"${repo}\" is not a valid plugin" && return 1 }
        ln -sf "${initfiles[1]}" "${initfile}"
    fi

    fpath+=${plugdir}
    if (( ${1} && $+functions[zsh-defer] )); then
        zsh-defer . ${initfile}
        if [[ "${3}" != 0 ]]; then
            local cb
            for cb in ${@:3}; do zsh-defer -c "${cb}"; done
        fi
    else
        . ${initfile}
        if [[ "${3}" != 0 ]]; then
            local cb
            for cb in ${@:3}; do eval "${cb}"; done
        fi
    fi
}

_ztupide_unload() {
    [ -z "${1}" ] && print "plugin unload error: none specified" && return 1

    local plugin_name="${1:t}"
    local plugin_path="${ZTUPIDE_PLUGIN_PATH}"/"${plugin_name}"

    if [ ! -d "${plugin_path}" ]; then
        print "plugin unload error: ${plugin_name} plugin not found"
        return 1
    fi

    if [ -d "${plugin_path}"/.git ]; then
        rm -rf "${plugin_path}"
        print "plugin ${plugin_name} removed"
    else
        read "ans?${plugin_name} is a local plugin. Do you want to unload it (y/N)? "
        if [[ "${ans}" =~ ^[Yy]$ ]]; then
            rm -rf "${plugin_path}"
            print "plugin ${plugin_name} removed"
        fi
    fi
}

_ztupide_update_plugin() {
    print "Checking ${1:t} for updates..."
    [ -z "$(git -C ${1} branch --list main)" ] && local branch="master" || local branch="main"
    git -C ${1} fetch origin "${branch}" --quiet
    local local=$(git -C ${1} rev-parse HEAD)
    local base=$(git -C ${1} rev-parse '@{u}')
    if [ "${local}" != "${base}" ]; then
        git -C ${1} reset --hard origin/"${branch}"
        git -C ${1} pull origin "${branch}" --quiet
        print "${1:t} updated"
    fi
    _ztupide_zcompile ${1} # compile plugin files if they have changed
}

_ztupide_update() {
    _ztupide_update_plugin ${_ztupide_path:h}

    local plugin_path
    for plugin_path in ${ZTUPIDE_PLUGIN_PATH}/*/.git(/N); do
        local plugin_file=("${plugin_path}"/*.{plugin.zsh,zsh-theme}(NY1))
        _ztupide_update_plugin ${plugin_path:h}
    done

    print "${EPOCHSECONDS}" > "${_ztupide_path:h}"/ztupide_last_update
}

_ztupide_autoupdate() {
    [ -z ${ZTUPIDE_AUTOUPDATE} ] && return

    if [ -f "${_ztupide_path:h}"/ztupide_last_update ]; then
        local delta=$(<"${_ztupide_path:h}"/ztupide_last_update)
        (( delta = ${EPOCHSECONDS} - ${delta} ))
        [ ${delta} -gt ${ZTUPIDE_AUTOUPDATE} ] && _ztupide_update_all
    else
        _ztupide_update_all
    fi
}

_ztupide_init() {
    _ztupide_path=${1:a}
    typeset -g _ztupide_loaded_theme

    ZTUPIDE_PLUGIN_PATH=${ZTUPIDE_PLUGIN_PATH:-${ZDOTDIR:-$HOME/.zsh}/plugins}
    ZTUPIDE_USE_ASYNC=${ZTUPIDE_USE_ASYNC:-1}

    # use zsh-defer if ZTUPIDE_USE_ASYNC is 1 to enable '--async' option with the 'ztupide load' command
    if (( ${ZTUPIDE_USE_ASYNC} )); then
        _ztupide_load 0 romkatv/zsh-defer
    fi

    # zcompile this file if it has changed (this ensures that ztupide.zsh is compiled on its first load)
    _ztupide_zcompile ${_ztupide_path:h}

    zmodload zsh/datetime
    _ztupide_autoupdate

    # add completion function to fpath
    fpath+=("${_ztupide_path:h}")
}

_ztupide_help() {
    print "Usage : ztupide OPTION [--async] [PLUGIN]

Options:
help\t\tshows this message
load\t\tload PLUGIN (asynchronously if --async used)
unload\t\tremove PLUGIN
update\t\tupdate ztupide and all plugins"
}

ztupide() {
    case "${1}" in
    load)
        local async
        if [ "${2}" = "--async" ]; then
            async=1
            shift
        fi
        [ -z "${2}" ] && print "plugin load error: none specified" && return 1
        _ztupide_load "${async:-0}" "${@:2}"
        ;;
    unload)
        _ztupide_unload "${2}"
        ;;
    update)
        _ztupide_update
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

# TODO async _ztupide_init
_ztupide_init ${0}
