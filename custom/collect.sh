#!/bin/bash
cd "$(dirname "$0")" || exit 1
rsync -avr --files-from=files.list ../zephyrproject/ files/
