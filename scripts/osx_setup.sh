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

# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 15 '{ enabled = 0; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 16 '{ enabled = 0; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 17 '{ enabled = 0; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 18 '{ enabled = 0; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 19 '{ enabled = 0; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 20 '{ enabled = 0; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 21 '{ enabled = 0; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 22 '{ enabled = 0; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 23 '{ enabled = 0; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 24 '{ enabled = 0; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 25 '{ enabled = 0; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 26 '{ enabled = 0; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 33 '{ enabled = 0; value = { parameters = (65535, 125, 8650752); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 36 '{ enabled = 0; value = { parameters = (65535, 103, 8388608); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 60 '{ enabled = 0; value = { parameters = (32, 49, 262144); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 61 '{ enabled = 0; value = { parameters = (32, 49, 786432); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 79 '{ enabled = 1; value = { parameters = (65535, 123, 8650752); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 80 '{ enabled = 1; value = { parameters = (65535, 123, 8781824); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 81 '{ enabled = 1; value = { parameters = (65535, 124, 8650752); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 82 '{ enabled = 1; value = { parameters = (65535, 124, 8781824); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 118 '{ enabled = 1; value = { parameters = (49, 18, 524288); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 119 '{ enabled = 1; value = { parameters = (50, 19, 524288); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 120 '{ enabled = 1; value = { parameters = (51, 20, 524288); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 121 '{ enabled = 1; value = { parameters = (52, 21, 524288); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 122 '{ enabled = 1; value = { parameters = (53, 23, 524288); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 164 '{ enabled = 0; value = { parameters = (65535, 65535, 0); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 175 '{ enabled = 0; value = { parameters = (65535, 65535, 0); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 190 '{ enabled = 0; value = { parameters = (113, 12, 8388608); type = standard; }; }'
# defaults write com.apple.symbolichotkeys.plist AppleSymbolicHotKeys -dict-add 222 '{ enabled = 0; value = { parameters = (65535, 65535, 0); type = standard; }; }'
