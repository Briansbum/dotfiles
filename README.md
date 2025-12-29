# dotfiles

my system configs managed with nix flakes. handles both nixos (mandelbrot) and nix-darwin (macbook).

## what's here

- `nix/` - system configurations for each machine
  - `mandelbrot/` - nixos desktop (nvidia gpu, niri compositor, ollama server)
  - `Alexs-Macbook-Pro/` - nix-darwin config for macos
  - `common/` - shared configuration between systems
- `config/` - dotfiles for various programs
  - `fish/` - shell config with custom functions and completions
  - `nvim/` - neovim setup
  - `ghostty/` - terminal emulator config
  - `yazi/` - file manager with tokyo-night theme
  - `starship.toml` - prompt config
  - `niri/` - compositor config (nixos only)
  - `rofi/` - launcher/menu system
  - `gh/`, `gopass/`, `argocd/`, `zed/` - tool configs
- `fonts/` - GoMono nerd font
- `scripts/` - utility scripts (aws helpers, git, hyprpaper, etc)
- `flake.nix` - defines all systems and their dependencies

## systems

### mandelbrot (nixos)
- niri compositor with nvidia prime offload
- ollama serving on tailnet (gpu accelerated)
- steam, bluetooth, pipewire audio
- auto-login to greeter

### macbook (nix-darwin)
- homebrew integration for gui apps and missing packages
- most cli tools via nix
- ghostty, zed, vscode, spotify, etc via casks

## managed configs

both systems use home-manager to symlink configs from this repo:
- fish shell (aliases, functions, paths, env vars)
- neovim with treesitter, packer
- git config (gpg signing, user info)
- tmux, starship, yazi, jq, fd, fzf, go
- ghostty with custom colorscheme

## setup

see setup.md for full details. nix-based setup is:

```bash
# install nix with flakes
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# get secrets from bitwarden (ssh keys, gpg)
# see setup.md

# for nixos:
sudo nixos-rebuild switch --flake github:Briansbum/dotfiles#mandelbrot

# for macos:
darwin-rebuild switch --flake github:Briansbum/dotfiles#Alexs-MacBook-Pro
```

## updating

the correct way (declarative, pulls from git):

```bash
# make changes, commit, push to github

# for nixos:
sudo nixos-rebuild switch --flake github:Briansbum/dotfiles#mandelbrot --refresh

# for macos:
darwin-rebuild switch --flake github:Briansbum/dotfiles#Alexs-MacBook-Pro --refresh
```

fast method for local testing (impure):

```bash
cd ~/devel/dotfiles

# for nixos:
sudo nixos-rebuild switch --flake .#mandelbrot

# for macos:
darwin-rebuild switch --flake .#Alexs-MacBook-Pro
```
