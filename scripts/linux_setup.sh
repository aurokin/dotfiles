#!/bin/bash

# curl -sL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh
# sudo bash nodesource_setup.sh
# rm nodesource_setup.sh

sudo apt-get update -y
sudo apt-get install -y build-essential 
# sudo apt-get install -y zsh nodejs build-essential wget ripgrep tree stow python3 openjdk-17-jdk openjdk-17-jre

chsh auro -s /bin/zsh
