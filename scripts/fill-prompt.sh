#!/usr/bin/env bash
# Fill a prompt template placeholder with a file's content, portably.
# Usage: fill-prompt.sh <template> <placeholder> <content-file> > out.md
set -euo pipefail
[ $# -eq 3 ] || { echo "usage: fill-prompt.sh <template> <placeholder> <content-file>" >&2; exit 1; }
python3 - "$1" "$2" "$3" << 'EOF'
import sys
template, placeholder, content = sys.argv[1], sys.argv[2], sys.argv[3]
with open(template) as t, open(content) as c:
    sys.stdout.write(t.read().replace(placeholder, c.read()))
EOF
