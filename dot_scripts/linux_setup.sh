#!/bin/bash

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$script_dir/apt_install.sh"

chsh auro -s /bin/zsh
