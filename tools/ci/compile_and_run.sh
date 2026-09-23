#!/bin/bash

RED='\033[0;31m'
NC='\033[0m'

source $HOME/BYOND/byond/bin/byondsetup

# Clean up between steps so Juke doesn't refuse to recompile with different -D options
rm -f deepquarry.dmb

# Copy example configs
cp config/example/* config/

# Create spritesheet directory
mkdir -p data/spritesheets

# Compile a copy of the codebase, and print errors as Github Actions annotations.
# TEST_BUILD=0 compiles the production build (live map) instead of the test world.
if [ "${TEST_BUILD:-1}" = "1" ]; then
  tools/build/build.sh --ci dm -DCIBUILDING -DCITESTING ${EXTRA_ARGS}
else
  tools/build/build.sh --ci dm -DCIBUILDING ${EXTRA_ARGS}
fi
exitVal=$?

# Compile failed
if [ $exitVal -gt 0 ]; then
  echo "${RED}Errors were produced during CI with arguments ${EXTRA_ARGS}, please review CI logs.${NC}"
  exit 1
fi

# This variable is set in the CI scripts depending if we need to run the codebase or not.
# Compile-only checks set it to 0.
if [ $RUN -eq 1 ];
then
  DreamDaemon deepquarry.dmb -close -invisible -trusted -verbose -params "log-directory=ci"
  cat data/logs/ci/clean_run.lk
fi
