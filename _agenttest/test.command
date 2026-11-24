#!/bin/bash
# Temporary: runs the new installer, then checks harkio the way an agent would.
cd "$(dirname "$0")"; HERE="$(pwd)"
{
echo "### install"; ../install.command < /dev/null; echo "exit $?"
echo; echo "### installed copy"; ls -l ~/.local/share/harkio; readlink ~/.local/bin/harkio
xattr -lr ~/.local/share/harkio | grep -c quarantine
for sh in "/bin/zsh -c" "/bin/bash -lc" "/bin/sh -c"; do
  echo; echo "### clean env: $sh"
  env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin $sh 'command -v harkio || echo NOT FOUND; harkio --version'
done
echo; echo "### narrate from /tmp with a clean env"
rm -rf /tmp/harkio_agent_test && mkdir -p /tmp/harkio_agent_test && cd /tmp/harkio_agent_test
printf '[0:00] Agents can run harkio now. [rate 160] Even with speed changes.\n' > t.txt
env -i HOME="$HOME" USER="$USER" PATH=/usr/bin:/bin /bin/zsh -c 'harkio t.txt'; echo "exit $?"
ls -l t_narration
} > "$HERE/log.txt" 2>&1
echo done > "$HERE/done.txt"
