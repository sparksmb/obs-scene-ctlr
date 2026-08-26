#!/bin/bash
# Stream Deck's "System: Open" runs this without sourcing .zshrc/.zprofile,
# so PATH won't include Homebrew or asdf. Set it explicitly so `ruby`
# resolves to the asdf-managed version with the project's gems installed,
# instead of falling back to macOS's built-in system Ruby.
export PATH="/opt/homebrew/bin:$HOME/.asdf/shims:$HOME/.asdf/bin:$PATH"
cd "$(dirname "$0")" || exit 1
exec ruby bin/run.rb loop
