#!/bin/sh
# Probe wrapper: drop files a failed writer test left behind under the
# compiled trees before the next verdict, then run the suite.
git clean -fdq -- src test fixture-lib
exec sh check.sh
