#!/usr/bin/env bash
# Run every stint test. Exit code is non-zero if any suite fails.
cd "$(dirname "$0")/.." || exit 1
status=0
bash tests/test_hook.sh || status=1
bash tests/test_install.sh || status=1
python3 -m unittest discover -s tests -p 'test_*.py' || status=1
exit $status
