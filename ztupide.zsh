#!/usr/bin/env zsh

# credits: https://github.com/mattmc3/zsh_unplugged, https://github.com/agkozak/zcomet

_ztupide_zcompile() {
    local f
    for f in ${1}/**/*.zsh{,-theme}(N); do
        [[ ! "${f}".zwc -nt "${f}" && -r "${f}" && -w "${f:h}" ]] && builtin zcompile $f
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

    if [[ -d ${plugdir}/functions ]]; then
        fpath+=${plugdir}/functions
    else
        fpath+=${plugdir}
    fi
    if [[ -d ${plugdir}/bin ]]; then
        path+=${plugdir}/bin
    fi
    zsh_loaded_plugins+=(${repo})

    if (( ${1} && $+functions[zsh-defer] )); then
        zsh-defer -dmpr -c "ZERO=${initfile} . ${initfile}"
        if [[ "${3}" != 0 ]]; then
            local cb
            for cb in ${@:3}; do zsh-defer -a -c "${cb}"; done
        fi
    else
        ZERO=${initfile} . ${initfile}
        if [[ "${3}" != 0 ]]; then
            local cb
            for cb in ${@:3}; do eval "${cb}"; done
        fi
    fi
}

_ztupide_cleanup_plugin() {
    (( ${+functions[${1}_plugin_unload]} )) && ${1}_plugin_unload

    # remove plugin from loaded plugins, fpath and path
    zsh_loaded_plugins=("${zsh_loaded_plugins[@]:#*${1}}")
    fpath=("${fpath[@]:#${ZTUPIDE_PLUGIN_PATH}/${1}}")
    fpath=("${fpath[@]:#${ZTUPIDE_PLUGIN_PATH}/${1}/functions}")
    path=("${path[@]:#${ZTUPIDE_PLUGIN_PATH}/${1}/bin}")
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
        _ztupide_cleanup_plugin "${plugin_name}"
        rm -rf "${plugin_path}"
        print "plugin ${plugin_name} removed"
    else
        read "ans?${plugin_name} is a local plugin. Do you want to unload it (y/N)? "
        if [[ "${ans}" =~ ^[Yy]$ ]]; then
            _ztupide_cleanup_plugin "${plugin_name}"
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
    typeset -g _ztupide_path=${1:a}
    # https://github.com/agkozak/Zsh-100-Commits-Club/blob/master/Zsh-Plugin-Standard.adoc#9-global-parameter-holding-the-plugin-managers-capabilities
    typeset -g PMSPEC=0fbuiPs
    typeset -g _ztupide_loaded_theme
    typeset -gUa zsh_loaded_plugins

    typeset -g ZTUPIDE_PLUGIN_PATH=${ZTUPIDE_PLUGIN_PATH:-${ZDOTDIR:-$HOME/.zsh}/plugins}

    # use zsh-defer if ZTUPIDE_DISABLE_ASYNC is 1 to enable '--async' option with the 'ztupide load' command
    (( ! ${+ZTUPIDE_DISABLE_ASYNC} )) && _ztupide_load 0 romkatv/zsh-defer

    typeset -g ZPFX
    : ${ZPFX:=${_ztupide_path:h}/polaris}
    [[ ! -d ${ZPFX} ]] && mkdir -p ${ZPFX}

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
            async=$(( ! ${+ZTUPIDE_DISABLE_ASYNC} ))
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

_ztupide_init ${0}
