#!/bin/sh
# Probe wrapper. The snapshot tests build fixture trees under test/ and
# fixture-lib/ and remove them at the end; a test that a mutant makes revert
# never reaches its cleanup, and the tree it left behind changes what the NEXT
# mutant's suite run sees (an existing <tag>/ is "already frozen"). Untracked
# fixture leftovers are cleared before every run so each verdict starts from the
# same tree. Tracked files are never touched: the mutation itself lives in one.
git clean -fdq test
rm -rf fixture-lib
exec sh ./check.sh
