# dotfiles

My personal shell environment and command-line tools, mainly for Linux and
NixOS systems.

It includes configurations for zsh, tmux, Vim, Git, and SSH, together with a
few utility scripts used across my machines.

## Highlights

- `riot`: an SSH wrapper with host presets, jump hosts, port forwarding, tmux
  sessions, and optional GPG agent forwarding.
- `sagt`: an SSH/GPG agent manager with support for PIV, 1Password, and
  OpenPGP smart cards.
- zsh aliases and completions for the bundled tools.
- tmux and Vim configurations with plugin setup.
- automatic updates with selectable `main`, `dev`, and `latest` channels.

## Installation

Quick install:

```sh
curl -fsSL https://dotfiles.cn | bash
```

Alternatively, clone the repository so the installer can be reviewed first:

```sh
git clone https://github.com/DictXiong/dotfiles.git ~/dotfiles
~/dotfiles/install.sh -a
```

The installer adds small source/include entries to the existing zsh, tmux,
Vim, and Git configuration files instead of replacing them entirely.

## Useful commands

```sh
riot --help                 # show the SSH wrapper manual
sagt                        # start or reuse an ssh-agent
sagt gpg                    # use gpg-agent as SSH agent
sagt gpg-pin                # cache the smart-card signature PIN
dfs update                  # update dotfiles from the selected channel
dfs config                  # edit machine-specific settings
```

## Configuration

Machine-specific settings can be placed in:

```text
~/.config/dotfiles/env
~/.config/riot-config.sh
```

This is a personal dotfiles repository. Review the configuration, SSH keys,
and installation script before using it on another machine.
