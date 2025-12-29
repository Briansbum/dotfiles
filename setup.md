# setup

## bootstrap process

complete fresh machine setup in order:

### 1. install bitwarden cli

get the cli to extract secrets:

```bash
# macos
brew install bitwarden-cli

# linux
wget https://github.com/bitwarden/clients/releases/download/cli-v2023.12.0/bw-linux-2023.12.0.zip
unzip bw-linux-2023.12.0.zip
sudo mv bw /usr/local/bin/
```

### 2. install nix

```bash
# on macos or linux
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

restart shell or source the nix profile.

### 3. get ssh keys from bitwarden

need the ssh key to clone the private repo:

```bash
# login to bitwarden
bw login freestone.alex@googlemail.com
export BW_SESSION="..." # copy from login output

# create ssh directory
mkdir -p ~/.ssh

# extract private key
bw get item "60a74143-b67c-4a81-8252-b0d500bb4414" | jq -r .notes | base64 -d | jq -r .private | base64 -d >~/.ssh/bitwarden

# set permissions
chmod 600 ~/.ssh/bitwarden

# extract public key
bw get item "60a74143-b67c-4a81-8252-b0d500bb4414" | jq -r .notes | base64 -d | jq -r .public | base64 -d >~/.ssh/bitwarden.pub
```

### 4. load ssh key

```bash
# start agent if needed
eval "$(ssh-agent -s)"

# add key
ssh-add ~/.ssh/bitwarden

# verify
ssh-add -l
```

### 5. get gpg key from bitwarden

need this for git commit signing:

```bash
# extract gpg key
bw get attachment --itemid="e1725819-64a8-410d-8ede-add800e156f3" "amg8ksjzum8xgi2pqjb3h33jimwz2omx"

# import it
gpg --import private.key
rm private.key

# trust the key
gpg --edit-key 873DF106014C63F7
# in gpg prompt: trust, select 5 (ultimate), quit
```

### 6. run nix rebuild

now everything's ready to build the system from github:

```bash
# for nixos (like mandelbrot):
sudo nixos-rebuild switch --flake github:Briansbum/dotfiles#mandelbrot

# for macos (like the macbook):
darwin-rebuild switch --flake github:Briansbum/dotfiles#Alexs-MacBook-Pro
```

that's it. all packages, configs, fonts, everything gets installed and symlinked.

### optional: local clone for development

if you want to iterate on configs locally:

```bash
mkdir -p ~/devel
cd ~/devel
git clone git@github.com:Briansbum/dotfiles.git
```

### what gets set up automatically

- fish shell (set as default, all configs/functions/completions)
- neovim with all plugins (run `:PackerSync` first time)
- git config (user info, gpg signing, push settings)
- tmux, starship prompt, yazi file manager
- ghostty terminal with custom theme
- all dev tools (go, python, node, rust, k8s tools, terraform, etc)
- fonts (GoMono nerd font)
- system configs (compositor, audio, services)

### nixos specific

mandelbrot gets:
- niri compositor with nvidia prime offload
- ollama with cuda serving on tailnet (systemd service)
- steam with proton
- bluetooth, pipewire audio, playerctl
- auto-login to greeter

### macos specific

macbook gets:
- homebrew managed by nix-darwin
- gui apps via casks (ghostty, zed, chrome, spotify, etc)
- tailscale, ollama as services
- gopass, 1password-cli for secrets

## updating the system

the correct way - commit and push changes, then rebuild from github:

```bash
cd ~/devel/dotfiles

# make changes to config files
# commit and push
git add .
git commit -m "whatever you changed"
git push

# rebuild from github with --refresh to pull latest
sudo nixos-rebuild switch --flake github:Briansbum/dotfiles#mandelbrot --refresh     # nixos
darwin-rebuild switch --flake github:Briansbum/dotfiles#Alexs-MacBook-Pro --refresh  # macos
```

fast method for local testing (impure, but useful when iterating):

```bash
cd ~/devel/dotfiles

# make changes

# rebuild from local directory
sudo nixos-rebuild switch --flake .#mandelbrot     # nixos
darwin-rebuild switch --flake .#Alexs-MacBook-Pro  # macos
```

## updating flake inputs

```bash
cd ~/devel/dotfiles

# update all inputs (nixpkgs, home-manager, etc)
nix flake update

# commit the updated flake.lock
git add flake.lock
git commit -m "update flake inputs"
git push

# rebuild from github
sudo nixos-rebuild switch --flake github:Briansbum/dotfiles#mandelbrot --refresh
# or
darwin-rebuild switch --flake github:Briansbum/dotfiles#Alexs-MacBook-Pro --refresh
```
