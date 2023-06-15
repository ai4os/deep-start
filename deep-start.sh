#!/usr/bin/env bash
#
# -*- coding: utf-8 -*-
#
# Copyright (c) 2018 - 2023 Karlsruhe Institute of Technology - Steinbuch Centre for Computing
# This code is distributed under the MIT License
# Please, see the LICENSE file
#
# @author: vykozlov

### info
# Start script for DEEP-OC containers
# Available options:
# -c|--cpu - force container on CPU only  (otherwise detected automatically)
# -g|--gpu - force GPU-related parameters (otherwise detected automatically)
# -d|--deepaas    - start deepaas-run
# -i|--install    - enforce that the latest git repo of the script is installed
# -j|--jupyterlab - start JupyterLab; if not installed, will be automatically installed
# -o|--onedata    - mount remote using oneclient
# -r|--rclone     - mount remote with rclone (experimental!) (comment this out for now!)
# -s|--vscode     - start VSCode (code-server); if not installed, will be automatically installed
# NOTE: if you try to start deepaas AND jupyterlab, only deepaas will start!
# ports for DEEPaaS, Monitoring, JupyterLab are automatically set based on presence of GPU
###

###
# In the DEEP-HDC/AI4OS platform the following environment settings are available:
# RCLONE_CONFIG
# RCLONE_CONFIG_RSHARE_URL
# RCLONE_CONFIG_RSHARE_VENDOR
# RCLONE_CONFIG_RSHARE_USER
# RCLONE_CONFIG_RSHARE_PASS
# jupyterPASSWORD
#
# The script setups:
# For JupyterLab, jupyter_notebook_config.py is used, which needs "jupyterPORT" environment
# Some applications need "monitoring port" (e.g. TensorBoard), which is fixed to "monitorPORT" environment

### Define defaults
# For AI4EOSC and iMagine, we change version to 2.
VERSION=2.0.2

## Define defaults for flags
cpu_mode=false
gpu_mode=false
use_deepaas=false
force_install=false
use_jupyter=false
use_rclone=false
use_onedata=false
use_vscode=false

debug_it=true

## Paths
script_install_dir="/srv/.deep-start"
script_git_repo="https://github.com/deephdc/deep-start"
script_git_branch="master"
vscode_workspace_file="srv.code-workspace"
vscode_extensions="vscode/code-server/vscode-extensions.txt"
# Script full path
# https://unix.stackexchange.com/questions/17499/get-path-of-current-script-when-executed-through-a-symlink/17500
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
# check if SCRIPT_DIR exists (not, if installed remotely?)
# if not => define as script_install_dir
[[ ! -d ${SCRIPT_DIR} ]] && SCRIPT_DIR=${script_install_dir}
# check if IDE_KEY_PATH and CERT_PATH exist, if not => put some default values (SSL)
[[ ! -v IDE_KEY_PATH ]] && IDE_KEY_PATH="${SCRIPT_DIR}/ssl/key.pem"
[[ ! -v IDE_CERT_PATH ]] && IDE_CERT_PATH="${SCRIPT_DIR}/ssl/cert.pem"

## Errors
onedata_error="2"
rclone_error="2"
deepaas_error="2"
jupyter_error="2"
install_error="2"
### end of defaults

# function to check if nvidia GPU is present
# has to be before check_arguments()
function check_nvidia()
{ if command nvidia-smi 2>/dev/null; then
    echo "[INFO] NVIDIA is present"
    cpu_mode=false
    gpu_mode=true
  else
    cpu_mode=true
    gpu_mode=false
  fi
}

function usage()
{
    shopt -s xpg_echo
    echo "Usage: $0 <options> \n
    Options:
    -h|--help \t\t the help message
    -c|--cpu \t\t force CPU-only execuition (otherwise detected automatically)
    -g|--gpu \t\t force GPU execution mode (otherwise detected automatically)
    -d|--deepaas \t start deepaas-run
    -i|--install \t enforce that the latest git repo of the deep-start script is installed
    -j|--jupyter \t start JupyterLab; if not installed, will be automatically installed
    -o|--onedata \t mount remote storage using oneclient
    -s|--vscode  \t start VSCode (code-server); if not installed, will be automatically installed
    -v|--version \t print script version and exit
    NOTE: if you try to start deepaas AND jupyterlab or vscode, only deepaas will start!" 1>&2; exit 0; 
# Comment possible RCLONE option. Leave it as "undocumented"
#    -r|--rclone  \t mount remote storage with rclone (experimental!)
}

function check_arguments()
{
    OPTIONS=hcgdijorsv
    LONGOPTS=help,cpu,gpu,deepaas,install,jupyter,onedata,rclone,vscode,version
    # https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
    # saner programming env: these switches turn some bugs into errors
    set -o errexit -o pipefail -o noclobber -o nounset
    #set  +o nounset
    ! getopt --test > /dev/null
    if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
        echo '`getopt --test` failed in this environment.'
        exit 1
    fi

    # -use ! and PIPESTATUS to get exit code with errexit set
    # -temporarily store output to be able to check for errors
    # -activate quoting/enhanced mode (e.g. by writing out “--options”)
    # -pass arguments only via   -- "$@"   to separate them correctly
    ! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        # e.g. return value is 1
        #  then getopt has complained about wrong arguments to stdout
        exit 2
    fi
    # read getopt’s output this way to handle the quoting right:
    eval set -- "$PARSED"

    if [ "$1" == "--" ]; then
        echo "[INFO] No arguments provided. Start deepaas as default"
        # check if NVIDIA-GPU is present
        check_nvidia
        use_deepaas=true
    fi

    # now enjoy the options in order and nicely split until we see --
    while true; do
        case "$1" in
            -h|--help)
                usage
                shift
                ;;
            -c|--cpu)
                cpu_mode=true
                shift
                ;;
            -g|--gpu)
                gpu_mode=true
                shift
                ;;
            -d|--deepaas)
                use_deepaas=true
                shift
                ;;
            -i|--install)
                force_install=true
                shift
                ;;
            -j|--jupyter)
                use_jupyter=true
                shift
                ;;
            -o|--onedata)
                use_onedata=true
                shift
                ;;
            -r|--rclone)
                use_rclone=true
                shift
                ;;
            -s|--vscode)
                use_vscode=true
                shift
                ;;
            -v|--version)
                echo $0
                echo "Version of the script: $VERSION"
                exit 0
                ;;
            --)
                shift
                break
                ;;
            *)
                break
                ;;
        esac
    done
}

function check_pid()
{
   pid=$1
   error_code=$2
   sleep 3
   for (( c=1; c<=3; c++ ))
   do
      if [ -n "$(ps -o pid= -p$pid)" ]; then
         sleep 3
      else
         echo "[ERROR] The process $pid stopped!"
         exit $error_code
      fi
   done
}

function check_env()
{
   param=$1
   error=$2
   echo "[INFO] Checking $param environment variable..."
   if [[ ! -v $param ]]; then
      echo "[ERROR] $param is not defined!"
      exit $error
   elif [[ -z "${!param}" ]]; then
      echo "[ERROR] $param is empty!"
      exit $error      
   fi   
}

check_nvidia
check_arguments "$0" "$@"

# set PORTs:
# 1. deepaas port
DEEPaaS_PORT=5000
[[ "$gpu_mode" = true && -v PORT0 ]] && DEEPaaS_PORT=$PORT0

# 2. need "monitoring port" for applications like TensorBoard
Monitor_PORT=6006
[[ "$gpu_mode" = true && -v PORT1 ]] && export Monitor_PORT=$PORT1
export monitorPORT=$Monitor_PORT

# 3. IDE port (e.g. JupyterLab or VSCode)
IDE_PORT=8888
[[ "$gpu_mode" = true && -v PORT2 ]] && IDE_PORT=$PORT2 


# if you try to start deepaas AND jupyterlab, only deepaas will start!
if [[ "$use_deepaas" = true && "$use_jupyter" = true ]]; then
   use_jupyter=false
   echo "[WARNING] You are trying to start DEEPaaS AND JupyterLab, only DEEPaaS will start!"
fi

# if you try to start deepaas AND vscode, only deepaas will start!
if [[ "$use_deepaas" = true && "$use_vscode" = true ]]; then
   use_vscode=false
   echo "[WARNING] You are trying to start DEEPaaS AND VSCode, only DEEPaaS will start!"
fi

# debugging printout
[[ "$debug_it" = true ]] && echo "[DEBUG] cpu: '$cpu_mode', gpu: '$gpu_mode', \
deepaas: '$use_deepaas', jupyter: '$use_jupyter', rclone: '$use_rclone', \
onedata: '$use_onedata', vscode: '$use_vscode'"

if [ "$force_install" = true ]; then
   # force installation of the deep-start script (most recent version from github)
   # this can be used to update the script and then start certain service:
   # one can execute e.g. "deep-start -i && deep-start -s"
   # or via docker cli : /bin/bash -c "deep-start -i && deep-start -s"

   echo "[WARNING] Force installation of the deep-start scripts from github!"
   echo "          Installing from ${script_git_repo} in ${script_install_dir}"
   # if directory exists and/or deep-start is found => delete them
   [[ -d $script_install_dir ]] && (cd /srv && rm -rf "$script_install_dir")
   [[ -f $(which deep-start) ]] && rm $(which deep-start)
   # re-create the directory
   [[ ! -d $script_install_dir ]] && (mkdir -p "$script_install_dir" && cd /srv)
   # clone the most recent version into the directory
   git clone --depth 1 -b ${script_git_branch} "${script_git_repo}" "${script_install_dir}"
   [[ $? -ne 0 ]] && echo "[ERROR] Could not clone ${script_git_repo}" && exit $install_error
   ln -f -s "${script_install_dir}/deep-start" /usr/local/bin/deep-start
   # print the deep-start version
   deep-start --version
fi

if [ "$use_onedata" = true ]; then
   # Mount ONEDATA point
   # Probably depricating in AI4OS
   echo "[INFO] Attempt to use ONEDATA"
   check_env ONECLIENT_ACCESS_TOKEN $onedata_error
   check_env ONECLIENT_PROVIDER_HOST $onedata_error
   #ONEDATA_SPACE
   [[ ! -v ONEDATA_MOUNT_POINT || -z "${ONEDATA_MOUNT_POINT}" ]] && ONEDATA_MOUNT_POINT="/mnt/onedata"
   # check if local mount point exists
   if [ ! -d "$ONEDATA_MOUNT_POINT" ]; then
      mkdir -p $ONEDATA_MOUNT_POINT
   fi
   cmd="oneclient $ONEDATA_MOUNT_POINT"
   echo "[ONEDATA] $cmd"
   # seems if started in the background, later gets another PID
   $cmd
   onedata_pid=$(pidof oneclient)
   echo "[ONEDATA] PID=$onedata_pid"
   check_pid "$onedata_pid" "$onedata_error"
   # if neither deepaas or jupyter is selected, enable deepaas:
   [[ "$use_deepaas" = false && "$use_jupyter" = false ]] && use_deepaas=true
fi

if [ "$use_rclone" = true ]; then
   # EXPERIMENTAL!
   echo "[INFO] Attempt to use RCLONE"
   check_env RCLONE_REMOTE_PATH $rclone_error
   [[ ! -v RCLONE_MOUNT_POINT || -z "${RCLONE_MOUNT_POINT}" ]] && RCLONE_MOUNT_POINT="/mnt/rclone"
   # check if local mount point exists
   if [ ! -d "$RCLONE_MOUNT_POINT" ]; then
      mkdir -p $RCLONE_MOUNT_POINT
   fi
   cmd="rclone mount --vfs-cache-mode full $RCLONE_REMOTE_PATH $RCLONE_MOUNT_POINT"
   echo "[RCLONE] $cmd"
   $cmd &
   rclone_pid=$!
   echo "[RCLONE] PID=$rclone_pid"
   check_pid "$rclone_pid" "$rclone_error"
   # if neither deepaas or jupyter is selected, enable deepaas:
   [[ "$use_deepaas" = false && "$use_jupyter" = false ]] && use_deepaas=true
fi

if [ "$use_deepaas" = true ]; then
   echo "[INFO] Attempt to start DEEPaaS"
   
   # Note: --openwhisk-detect is not needed in this case, and deprecated for removal
   cmd="deepaas-run --listen-ip=0.0.0.0 --listen-port=$DEEPaaS_PORT"
   echo "[DEEPaaS] $cmd"
   $cmd
   # we can't put process in the background, as the container will stop
fi

if [ "$use_jupyter" = true ]; then
   echo "[INFO] Attempt to start JupyterLab"

   # if jupyter-lab is requested and not installed, install it
   # check if jupyter-lab is installed
   if command jupyter-lab --version 2>/dev/null; then
      echo "[INFO] jupyterlab found!"
   else
      echo "[INFO] jupyterlab is NOT found! Trying to install.."
      pip3 install jupyterlab
   fi

   # check if JUPYTER_CONFIG_DIR is NOT set, set to ${SCRIPT_DIR}
   [[ ! -v JUPYTER_CONFIG_DIR || -z "${JUPYTER_CONFIG_DIR}" ]] && JUPYTER_CONFIG_DIR="${SCRIPT_DIR}"

   # check if jupyter_notebook_config.py exists
   [[ ! -f "${JUPYTER_CONFIG_DIR}/jupyter_notebook_config.py" ]] && JUPYTER_CONFIG_DIR="${SCRIPT_DIR}"
   export JUPYTER_CONFIG_DIR="${JUPYTER_CONFIG_DIR}"

   # add certificates if they exist
   if [ -f "${IDE_KEY_PATH}" ] && [ -f "${IDE_CERT_PATH}" ]; then
      jupyterCERT=" --keyfile=$IDE_KEY_PATH --certfile=$IDE_CERT_PATH"
   else
      jupyterCERT=""
   fi

   # if user-defined jupyterOPTS env not set, set to empty
   [[ ! -v jupyterOPTS ]] && jupyterOPTS=""
 
   cmd="jupyter lab $jupyterOPTS $jupyterCERT"
   echo "[Jupyter] JUPYTER_CONFIG_DIR=${JUPYTER_CONFIG_DIR}, jupyterPORT=$IDE_PORT, $cmd"
   export jupyterPORT=$IDE_PORT
   $cmd
   # we can't put process in the background, as the container will stop
fi

if [ "$use_vscode" = true ]; then
   echo "[INFO] Attempt to start VSCode server"

   # if code-server is requested and not installed, install it
   # check if code-server is installed
   if command code-server --version 2>/dev/null; then
      echo "[INFO] code-server (VSCode) is found!"
   else
      echo "[INFO] code-server (VSCode) is NOT found! Trying to install.."
      curl -fsSL https://code-server.dev/install.sh | sh
   fi

   # add certificates if they exist
   if [ -f "${IDE_KEY_PATH}" ] && [ -f "${IDE_CERT_PATH}" ]; then
      vscodeCERT=" --cert-key ${IDE_KEY_PATH} --cert=${IDE_CERT_PATH}"
   else
      vscodeCERT=""
   fi

   # (work-around) currently we setup jupyterPASSWORD on the platform while deploying
   [[ ! -v PASSWORD ]] && export PASSWORD=$jupyterPASSWORD

   # if there is no workspace file, put default one (not sure if needed...)
   [[ ! -f "$vscode_workspace_file" ]] && (cp ${SCRIPT_DIR}/vscode/$vscode_workspace_file $vscode_workspace_file)

   # install extensions from $vscode_extensions path (see top)
   # https://stackoverflow.com/questions/8195950/reading-lines-in-a-file-and-avoiding-lines-with-with-bash
   vscode_extensions=${SCRIPT_DIR}/${vscode_extensions}
   if [ -f "$vscode_extensions" ]; then
      # allow comments started with '#'
      grep -v '^#' ${vscode_extensions} | while read -r wl
      do
      # skip empty lines
         if [ ${#wl} -ge 5 ]; then
            code-server --user-data-dir=${SCRIPT_DIR}/vscode/code-server/ --install-extension "${wl}" || continue
         fi
      done
   fi

   cmd="code-server --disable-telemetry --bind-addr 0.0.0.0:$IDE_PORT --user-data-dir=${SCRIPT_DIR}/vscode/code-server/ ${vscodeCERT}"
   echo "[VSCode] PORT=$IDE_PORT, $cmd"
   $cmd
   # we can't put process in the background, as the container will stop
fi
