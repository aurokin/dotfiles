#!/bin/bash

set -e

command -v npm >/dev/null 2>&1
npm uninstall -g @anthropic-ai/claude-code @openai/codex opencode-ai
