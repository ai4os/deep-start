#!/usr/bin/env bash
#
# -*- coding: utf-8 -*-
#
# Copyright (c) 2018 - 2020 Karlsruhe Institute of Technology - Steinbuch Centre for Computing
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
# -j|--jupyterlab - start jupyterlab
# -o|--onedata    - mount remote using oneclient
# -r|--rclone     - mount remote with rclone (experimental!)
# -s|--vscode     - start VSCode (code-server)
# NOTE: if you try to start deepaas AND jupyterlab, only deepaas will start!
# ports for DEEPaaS, Monitoring, JupyterLab are automatically set based on presence of GPU
###

debug_it=true

# Script full path
# https://unix.stackexchange.com/questions/17499/get-path-of-current-script-when-executed-through-a-symlink/17500
SCRIPT_PATH="$(dirname "$(readlink -f "$0")")"
KEY_PATH="${SCRIPT_PATH}/ssl/key.pem"
CERT_PATH="${SCRIPT_PATH}/ssl/cert.pem"


function usage()
{
    shopt -s xpg_echo
    echo "Usage: $0 <options> \n
    Options:
    -h|--help \t\t the help message
    -c|--cpu \t\t force CPU-only execuition (otherwise detected automatically)
    -g|--gpu \t\t force GPU execution mode (otherwise detected automatically)
    -d|--deepaas \t start deepaas-run
    -i|--install \t check that the full repo is installed
    -j|--jupyter \t start JupyterLab, if installed
    -o|--onedata \t mount remote storage using oneclient
    -r|--rclone  \t mount remote storage with rclone (experimental!)
    -s|--vscode  \t start VSCode (code-server), if installed
    NOTE: if you try to start deepaas AND jupyterlab or vscode, only deepaas will start!" 1>&2; exit 0; 
}

# define flags
cpu_mode=false
gpu_mode=false
use_deepaas=false
check_install=false
script_install_path="/srv/.deep-start"
script_git_repo="https://github.com/deephdc/deep-start"
use_jupyter=false
use_rclone=false
use_onedata=false
use_vscode=false

onedata_error="2"
rclone_error="2"
deepaas_error="2"
jupyter_error="2"
install_error="2"

function check_nvidia()
{ # check if nvidia GPU is present
  if command nvidia-smi 2>/dev/null; then
    echo "[INFO] NVIDIA is present"
    cpu_mode=false
    gpu_mode=true
  else
    cpu_mode=true
    gpu_mode=false
  fi
}

function check_arguments()
{
    OPTIONS=hcgdijors
    LONGOPTS=help,cpu,gpu,deepaas,install,jupyter,onedata,rclone,vscode
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
                check_install=true
                shift
                ;;
            -j|--jupyter)
                use_jupyter=true
                shift
                ;;
            -r|--rclone)
                use_rclone=true
                shift
                ;;
            -o|--onedata)
                use_onedata=true
                shift
                ;;
            -s|--vscode)
                use_vscode=true
                shift
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

function check_install()
{
   # function to check that jupyter scripts are installed

   path=$1
   jupyter_check_one=false
   jupyter_check_two=false

   # skip checking -d ${path}/lab, as this dir was introduced recently
   if [ -f "${path}/jupyter_notebook_config.py" ]; then
      echo "[INFO] jupyter_notebook_config.py is found!"
      jupyter_check_one=true
   else
      echo "[WARNING] jupyter_notebook_config.py is NOT found in ${path}!"
   fi

   if [ -f "${path}/run_jupyter.sh" ]; then
      echo "[INFO] run_jupyter.sh is found!"
      jupyter_check_two=true
   else
      echo "[WARNING] run_jupyter.sh is NOT found in ${path}!"
   fi

   if [[ "$jupyter_check_one" = true && "$jupyter_check_two" = true ]]; then
      script_installed=true
   fi
}

function create_self_cert()
{
  # function to create self-signed certificate
  openssl req -x509 -newkey rsa:4096 \
-keyout ${KEY_PATH} \
-out ${CERT_PATH} -sha256 -days 365 \
-subj "/O=DEEP-HDC/OU=Development/CN=$HOSTNAME" -nodes -sha256

}

check_nvidia
check_arguments "$0" "$@"

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

if [ "$check_install" = true ]; then
   # check if corresponding jupyter scripts are installed
   # either in a local directory or in the pre-defined path

   # check them locally
   script_installed=false
   check_install "${SCRIPT_PATH}"
   script_installed_loc=$script_installed

   #.. or in the pre-defined path (reset script_installed!)
   script_installed=false
   check_install "${script_install_path}"
   script_installed_pre=$script_installed

   # if not installed in either path, force installation in the pre-defined path
   if [[ "$script_installed_loc" = false &&  "$script_installed_pre" = false ]]; then
      echo "[WARNING] deep-start scripts were NOT found!"
      echo "          Installing from ${script_git_repo} in ${script_install_path}"
      [[ ! -d $script_install_path ]] && mkdir -p "$script_install_path"
      git clone "${script_git_repo}" "${script_install_path}"
      # ToDo: may need to PULL, not only CLONE! i.e. force update
      [[ $? -ne 0 ]] && echo "[ERROR] Could not clone ${script_git_repo}" && exit $install_error
      ln -f -s "${script_install_path}/deep-start" /usr/local/bin/deep-start
   else
     echo "[INFO] deep-start scripts found in:"
     [[ "$script_installed_loc" = true ]] && echo "    * ${SCRIPT_PATH}" 
     [[ "$script_installed_pre" = true ]] && echo "    * ${script_install_path}" 
   fi
   # if scripts are not installed locally, they are either
   # already installed in pre-defined path or just installed by git clone
   [[ "$script_installed_loc" = false ]] && SCRIPT_PATH=${script_install_path}

   # if jupyter-lab is requested and not installed, install it
   if [ "$use_jupyter" = true ]; then
      # check if jupyter is installed
      if command jupyter-lab --version 2>/dev/null; then
         echo "[INFO] jupyterlab found!"
      else
         echo "[INFO] jupyterlab is NOT found! Trying to install.."
         pip3 install jupyterlab
      fi
   fi
fi

if [ "$use_onedata" = true ]; then
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
   DEEPaaS_PORT=5000
   [[ "$gpu_mode" = true && -v PORT0 ]] && DEEPaaS_PORT=$PORT0
   export monitorPORT=6006
   [[ "$gpu_mode" = true && -v PORT1 ]] && export monitorPORT=$PORT1
   cmd="deepaas-run --openwhisk-detect --listen-ip=0.0.0.0 --listen-port=$DEEPaaS_PORT"
   echo "[DEEPaaS] $cmd"
   $cmd
   # we can't put process in the background, as the container will stop
fi

if [ "$use_jupyter" = true ]; then
   echo "[INFO] Attempt to start JupyterLab"

   # check if JUPYTER_CONFIG_DIR is NOT set, set to ${SCRIPT_PATH}
   [[ ! -v JUPYTER_CONFIG_DIR || -z "${JUPYTER_CONFIG_DIR}" ]] && JUPYTER_CONFIG_DIR="${SCRIPT_PATH}"

   # check if jupyter_notebook_config.py exists
   [[ ! -f "${JUPYTER_CONFIG_DIR}/jupyter_notebook_config.py" ]] && JUPYTER_CONFIG_DIR="${SCRIPT_PATH}"
   export JUPYTER_CONFIG_DIR="${JUPYTER_CONFIG_DIR}"

   Jupyter_PORT=8888
   [[ "$gpu_mode" = true && -v PORT2 ]] && Jupyter_PORT=$PORT2

   export monitorPORT=6006
   [[ "$gpu_mode" = true && -v PORT1 ]] && export monitorPORT=$PORT1

   # add self-signed certificates for secure connection, if do not exist
   [[ ! -f "${KEY_PATH}" && ! -f "${CERT_PATH}" ]] && create_self_cert
   jupyterCERT=" --keyfile=$KEY_PATH --certfile=$CERT_PATH"

   # if jupyterOPTS env not set, create it empty
   [[ ! -v jupyterOPTS ]] && jupyterOPTS=""
 
   cmd="jupyter lab $jupyterOPTS $jupyterCERT --allow-root"
   echo "[Jupyter] JUPYTER_CONFIG_DIR=${JUPYTER_CONFIG_DIR}, jupyterPORT=$Jupyter_PORT, $cmd"
   export jupyterPORT=$Jupyter_PORT  
   $cmd
   # we can't put process in the background, as the container will stop
fi

if [ "$use_vscode" = true ]; then
   echo "[INFO] Attempt to start VSCode server"

   export VSCode_PORT=8888
   [[ "$gpu_mode" = true && -v PORT2 ]] && export VSCode_PORT=$PORT2

   export monitorPORT=6006
   [[ "$gpu_mode" = true && -v PORT1 ]] && export monitorPORT=$PORT1

   # add self-signed certificates for secure connection, if do not exist
   [[ ! -f "${KEY_PATH}" && ! -f "${CERT_PATH}" ]] && create_self_cert

   cmd="code-server --disable-telemetry --port $VSCode_PORT --user-data-dir=/srv/.deep-start/vscode/code-server/ --cert ${CERT_PATH} --cert-key ${KEY_PATH}"
   echo "[VSCode] PORT=$VSCode_PORT, $cmd"
   export jupyterPORT=$VSCode_PORT
   $cmd
   # we can't put process in the background, as the container will stop
fi
