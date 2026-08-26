#!/bin/bash
# Shows a live view of everything run.rb has logged, including runs
# triggered from Stream Deck buttons (which have no visible terminal of
# their own). Leave this running in a terminal window during the broadcast.
cd "$(dirname "$0")" || exit 1
mkdir -p logs
touch logs/controller.log
exec tail -f logs/controller.log
