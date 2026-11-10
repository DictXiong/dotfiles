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

### Signed updates

To protect the SSH authorized keys, updates verify the commit signature and
use the committer time. If that signature cannot be verified, they verify
the OpenPGP-signed `dfs-release/<full-commit-id>` tag and use its tagger time.
An update must be strictly newer than the installed revision when both can
be verified. For a GitHub merge, push the signed tag before advancing the
release pointer. For a trusted first install, verify the starting revision
with an independently obtained public key before running the installer.

Without GnuPG, the installer warns and updates without verification for that
run. For future updates, install GnuPG or set `DFS_IGNORE_COMMIT_SIGN=1`
in `~/.config/dotfiles/env` to explicitly skip verification.

## Nix

Add `inputs.dotfiles.url = "github:DictXiong/dotfiles";` to your flake.
The dotfiles flake has no inputs of its own.

- `dotfiles.lib.ssh.authorizedKeys` is the list of entries from
  `.ssh/authorized_keys2`, in file order, with blank and comment lines removed.
- `dotfiles.lib.ssh.selectAuthorizedKeys` takes a list of SSH key comments and
  returns the matching entries in the requested order. It matches plain
  `type key comment` entries and fails if a comment is missing or ambiguous.
- `dotfiles.lib.files` exposes paths to `authorizedKeys`,
  `authorizedCertificates` (the EID certificate bundle), `git`, `tmux`, `vim`,
  and `zsh`. Use these paths to reference the original files.

For a NixOS module that receives the flake's `inputs` via `specialArgs`, set
the following option with the comments of the keys you want to authorize.

```nix
users.users.root.openssh.authorizedKeys.keys =
  inputs.dotfiles.lib.ssh.selectAuthorizedKeys [ "your-key-comment" ];
```

Run `nix eval path:.#lib.ssh.authorizedKeys --json` from this checkout to
inspect the full list.

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
