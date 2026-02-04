#!/bin/bash

mise install
mise upgrade
eval "$(mise activate bash)"

python -m pip install --user pipx

corepack enable
npm install -g @fsouza/prettierd
npm install -g @vue/typescript-plugin typescript-language-server
npm install -g @google/gemini-cli
npm install -g @github/copilot
gem install cocoapods fastlane

python -m pipx install beautysh
python -m pipx install httpie
python -m pipx install ranger-fm

mise reshim

echo "Resolved tools:"
command -v prettierd pod fastlane beautysh http httpie ranger gemini copilot || true

echo "Tool versions:"
prettierd --version || true
gemini --version || true
copilot --version || true
pod --version || true
fastlane --version || true
beautysh --version || true
http --version || true
ranger --version || true
