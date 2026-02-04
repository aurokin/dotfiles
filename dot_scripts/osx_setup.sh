#!/bin/bash

defaults write -g NSWindowShouldDragOnGesture YES
defaults write -g NSAutomaticWindowAnimationsEnabled -bool false
defaults write com.apple.finder DisableAllAnimations -bool true
defaults write com.apple.dock launchanim -bool false
defaults write -g NSWindowResizeTime -float 0.001
defaults write com.apple.dock expose-animation-duration -float 0.1
defaults write com.apple.dock autohide-time-modifier -float 0
defaults write com.apple.mail DisableReplyAnimations -bool true
defaults write com.apple.HIToolbox AppleFnUsageType -int 0
defaults write NSGlobalDomain com.apple.mouse.linear -int 1
defaults write NSGlobalDomain com.apple.mouse.scaling -float 0.875
defaults write NSGlobalDomain com.apple.trackpad.forceClick -int 0
defaults write NSGlobalDomain com.apple.swipescrolldirection -boolean NO
defaults write NSGlobalDomain AppleSpacesSwitchOnActivate -int 1
defaults write com.apple.dock autohide -int 1
defaults write com.apple.dock mod-count -int 41
defaults write com.apple.dock mru-spaces -int 0
defaults write com.apple.Spotlight engagementCount-com.apple.Spotlight -int 1
defaults write com.apple.Spotlight engagementCount-com.apple.Spotlight.suggestions -int 0
defaults write com.apple.Spotlight engagementCount-com.apple.mail -int 0
defaults write com.apple.AppleMultitouchTrackpad ActuateDetents -int 1
defaults write com.apple.AppleMultitouchTrackpad Clicking -int 1
defaults write com.apple.AppleMultitouchTrackpad FirstClickThreshold -int 0
defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -int 1
defaults write com.apple.AppleMultitouchTrackpad SecondClickThreshold -int 0
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture -int 2
defaults write com.apple.preference.trackpad ForceClickSavedState -int 1
defaults write com.apple.dock "show-recents" -bool "false"
defaults write com.apple.Accessibility ReduceMotionEnabled -int 1
defaults write -g NSRequiresAquaSystemAppearance -bool No
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"
