#!/bin/bash
# Re-renders the long timing test narration with the current System Voice.
cd "$(dirname "$0")"
../harkio long_test_script.txt 2>&1 | tee regenerate_voice.log
echo "EXIT: ${PIPESTATUS[0]}" >> regenerate_voice.log
