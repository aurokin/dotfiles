#!/bin/bash
if [[ $OS == "darwin" ]]; then
    # OSX
    sh <(curl -L https://nixos.org/nix/install)
else
    # Unix, may require sudo
    sh <(curl -L https://nixos.org/nix/install) --daemon
fi
