#!/usr/bin/env fish
if [ -f '/Users/alex/Downloads/google-cloud-sdk/path.fish.inc' ]; . '/Users/alex/Downloads/google-cloud-sdk/path.fish.inc'; end

# Add gcloud to PATH if installed via Homebrew
if test -d /opt/homebrew/Caskroom/gcloud-cli/latest/google-cloud-sdk/bin
    set PATH "$PATH:/opt/homebrew/Caskroom/gcloud-cli/latest/google-cloud-sdk/bin/"
end
