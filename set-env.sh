#!/bin/bash

if [ -z "${EDK_TOOLS_PATH}" ]; then
  export REPO=$(pwd)
  export GCC5_X64_PREFIX=x86_64-linux-gnu-
  pushd ${REPO}/edk2
  source edksetup.sh
  popd
fi
