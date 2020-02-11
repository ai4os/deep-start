#!/usr/bin/env bash
# Copyright 2015 The TensorFlow Authors. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ==============================================================================
# 
# modified by v.kozlov @2018-07-18 
# to include jupyterCONFIG_URL environment check
#
######

# Script full path
SCRIPT_PATH="$( cd $(dirname $0) ; pwd -P )"

if [[ ! -v jupyterOPTS ]]; then
    jupyterOPTS=""
fi

# Check if jupyterCONFIG_URL environment is specified 
# (can be passed to docker via "-e jupyterCONFIG_URL=value")
# If so, try to download using rclone:
#    jupyterSSL.key   - private key file for usage with SSL/TLS
#    jupyterSSL.pem   - SSL/TLS certificate file
if [[ ! -z "${jupyterCONFIG_URL}" ]]; then
    DEST_DIR="${SCRIPT_PATH}/ssl/"
    cmd_rclone=$(rclone copy $jupyterCONFIG_URL $DEST_DIR)

    PEM_PATH=${DEST_DIR}jupyterSSL.pem
    KEY_PATH=${DEST_DIR}jupyterSSL.key

    [[ -f $KEY_PATH ]] && jupyterOPTS=$jupyterOPTS" --keyfile=u'$KEY_PATH'"
    [[ -f $PEM_PATH ]] && jupyterOPTS=$jupyterOPTS" --certfile=u'$PEM_PATH'"
fi

# mainly for debugging:
echo "opts: $jupyterOPTS"

# activate "Quit" button: do not do this, server shuts down!
#jupyter lab --LabApp.quit_button=True $jupyterOPTS "$@"

jupyter lab $jupyterOPTS "$@"
