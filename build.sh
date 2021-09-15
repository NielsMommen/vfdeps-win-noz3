#!/bin/bash

set -e # Stop as soon as a command fails.
set -x # Print what is being executed.

pwd
VFDEPS_VERSION=`git describe --always`
VFDEPS_DIRNAME=vfdeps
MSVC_INSTALL_DIR=${1:="C:/vfMinVS"}

BUILD_DIR=`pwd`
mkdir upload
UPLOAD_DIR=$BUILD_DIR/upload

VFDEPS_PARENT_DIR=C:/
VFDEPS_PLATFORM=win

VFDEPS_DIR=$VFDEPS_PARENT_DIR/$VFDEPS_DIRNAME
mkdir $VFDEPS_DIR
/c/cygwin/bin/bash -lc "cd /cygdrive/$BUILD_DIR && make PREFIX=$VFDEPS_DIR"

if [[ ! -v GITHUB_ENV ]]; then
    CXX_DEPS_FLAGS="-minimize_disk_usage"
fi
powershell.exe -ExecutionPolicy RemoteSigned -File build_cxx_deps.ps1 -msvc_install_dir "$MSVC_INSTALL_DIR" -vfdeps_dir "$VFDEPS_DIR" $CXX_DEPS_FLAGS

VFDEPS_FILENAME=$VFDEPS_DIRNAME-$VFDEPS_VERSION-$VFDEPS_PLATFORM-noz3.txz
VFDEPS_FILEPATH=$UPLOAD_DIR/$VFDEPS_FILENAME
cd $VFDEPS_PARENT_DIR
tar cjf $VFDEPS_FILEPATH $VFDEPS_DIRNAME
cd $BUILD_DIR

ls -l $VFDEPS_FILEPATH
shasum -a 224 $VFDEPS_FILEPATH
