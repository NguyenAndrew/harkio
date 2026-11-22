#!/usr/bin/env bash
# Kept for old habits: same as "harkio narrate ..."
exec "$(cd "$(dirname "$0")" && pwd)/harkio" narrate "$@"
