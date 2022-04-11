# Ztupide

A simple and fast zsh plugin manager. It uses zcompile and async loading to speed up your shell startup time.

## Installation

Place this at the top of your .zshrc file but below compinit (or you won't have ztupide completions):

```zsh
[ -f ~/.zsh/ztupide/ztupide.zsh ] || git -C ~/.zsh clone https://github.com/mpostaire/ztupide
source ~/.zsh/ztupide/ztupide.zsh
```
This will source ztupide after installing it if necessary.

## Configuration

You can set variables to change the behaviour of ztupide (they must be set before you source ztupide):

| Variable | Effect |
|-|-|
| ZTUPIDE_PLUGIN_PATH | Plugins installation path (default: `~/.zsh/plugins`) |
| ZTUPIDE_AUTOUPDATE  | Check for updates interval in seconds (no autoupdates if unset). |

## Usage

Ztupide supports "local" and "remote" plugins and must use the `.plugin.zsh` or `.zsh-theme` extension. Local plugins are manually installed in the ZTUPIDE_PLUGIN_PATH while remote plugins are git repositories cloned from github.

Use `ztupide load user/plugin_name` to load a remote plugin (only github is supported) and `ztupide load plugin_name` to load a local plugin. You can use async mode like this: `ztupide load --async user/plugin_name`. Plugins loaded in async mode are guaranteed to be sourced in the same order as they are loaded. You can also add callbacks after the plugin is loaded like this: `ztupide load --async user/plugin_name callback1 callback2 ...`.

To remove a plugin use `ztupide remove plugin_name`. A prompt will ask for confirmation if it's a local plugin.

To update ztupide and all its plugins use `ztupide update`.

## Example

```zsh
[ -f ~/.zsh/ztupide/ztupide.zsh ] || git -C ~/.zsh clone https://github.com/mpostaire/ztupide
ZTUPIDE_AUTOUPDATE=604800 # autoupdate interval of 7 days
source ~/.zsh/ztupide/ztupide.zsh

# load remote plugin in async mode
ztupide load --async zdharma/fast-syntax-highlighting

# load local plugin installed in $ZTUPIDE_PLUGIN_PATH/zsh-colored-ls
ztupide load zsh-colored-ls

# set variable before loading its plugin
ZSH_AUTOSUGGEST_USE_ASYNC=1
# call _zsh_autosuggest_start function after the plugin is loaded.
ztupide load --async zsh-users/zsh-autosuggestions _zsh_autosuggest_start

# Here fast-syntax-highlighting and zsh-autosuggestions may still be
# loading but it's guaranteed that fast-syntax-highlighting will be
# sourced before zsh-autosuggestions.
```
