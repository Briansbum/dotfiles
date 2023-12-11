# How to setup for alex

# Ubuntu-22.04 LTS

```
sudo apt update
sudo apt upgrade -y
```

install neovim
```
wget https://github.com/neovim/neovim/releases/download/stable/nvim-linux64.tar.gz
tar xvzf nvim-linux64.tar.gz
mkdir -p ~/bin
mv nvim-linux64 ~/bin/
sudo ln -s ~/bin/nvim-linux64/bin/nvim /usr/local/bin/nvim 
```

install required packages:
`sudo apt install unzip jq zsh build-essential libc6 libluajit-5.1-2 libmsgpackc2 libtermkey1 libtree-sitter0 libunibilium4 libuv1 libvterm0 lua-luv python3-pynvim xclip xsel xxd nodejs npm`

set zsh as default shell
`chsh -s $(which zsh)`

logout/in or just run zsh

install oh-my-zsh
`sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"`

Get BW CLI
`wget https://github.com/bitwarden/clients/releases/download/cli-v2023.12.0/bw-linux-2023.12.0.zip`

unzip it and move to /usr/local/bin or wherever

run `bw login freestone.alex@googlemail.com` and complete login with pw/2fa

export the session token as instructed

start getting secrets:
```
mkdir -p ~/.ssh
bw get item "60a74143-b67c-4a81-8252-b0d500bb4414" | jq -r .notes | base64 -d | jq -r .private | base64 -d >~/.ssh/bitwarden
chmod 600 ~/.ssh/bitwarden
bw get item "60a74143-b67c-4a81-8252-b0d500bb4414" | jq -r .notes | base64 -d | jq -r .public | base64 -d >~/.ssh/bitwarden.pub
```

get the key into the agent with this:
```
cat >>~/.zshrc <<EOF
if ! stat /tmp/ssh_agent >/dev/null 2>&1; then
        ssh-agent -s >/tmp/ssh_agent
fi
if ! ssh-add -L >/dev/null 2>&1; then
        eval \`cat /tmp/ssh_agent\`
        ssh-add ~/.ssh/bitwarden
fi
EOF
```

Do the gpg thing

```
bw get attachment --itemid="e1725819-64a8-410d-8ede-add800e156f3" "amg8ksjzum8xgi2pqjb3h33jimwz2omx"
gpg --import private.key
rm private.key
gpg --edit 873DF106014C63F7
```

once you are in the gpg prompt run `trust` and select `5` for ultimate, confirm and then exit gpg

```
echo 'export GPG_TTY=$(tty)' >>~/.zshrc
git config --global user.signingkey A0E7C0BF628420C273078074873DF106014C63F7
git config --global commit.gpgsign true
git config --global user.name "Alex Freestone"
git config --global user.email "freestone.alex@gmail.com"
```

get dotfiles, install nvim dotfiles
```
mkdir -p ~/devel
cd ~/devel
git clone git@github.com:Briansbum/dotfiles.git
mkdir -p ~/.config/nvim
ln -s ~/devel/dotfiles/nvim ~/.config/ 
```

bootstrap nvim with `:PackerSync`
