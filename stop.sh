#!/bin/bash
export PATH="/opt/homebrew/bin:$HOME/.asdf/shims:$HOME/.asdf/bin:$PATH"
cd "$(dirname "$0")" || exit 1
exec ruby bin/run.rb stop
