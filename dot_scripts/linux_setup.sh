#!/bin/bash

# curl -sL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh
# sudo bash nodesource_setup.sh
# rm nodesource_setup.sh

sudo apt-get update -y
sudo apt-get install -y build-essential openjdk-21-jdk python3 nodejs ruby-full lua5.4 liblua5.4-dev golang

chsh auro -s /bin/zsh
