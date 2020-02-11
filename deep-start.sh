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
# NOTE: if you try to start deepaas AND jupyterlab, only deepaas will start!
###


debug_it=true

function usage()
{
    shopt -s xpg_echo
    echo "Usage: $0 <options> \n
    Options:
    -h|--help \t\t the help message
    -c|--cpu \t\t force CPU-only execuition (otherwise detected automatically)
    -g|--gpu \t\t force GPU execution mode (otherwise detected automatically)
    -d|--deepaas \t start deepaas-run
    -j|--jupyter \t start JupyterLab, if installed
    -o|--onedata \t mount remote storage usinge oneclient
    -r|--rclone  \t mount remote storage with rclone (experimental!)
    NOTE: if you try to start deepaas AND jupyterlab, only deepaas will start!" 1>&2; exit 0; 
}

# define flags
cpu_mode=false
gpu_mode=false
use_deepaas=false
use_jupyter=false
use_rclone=false
use_onedata=false

onedata_error="3"
rclone_error="4"
deepaas_error="5"
jupyter_error="6"

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
    OPTIONS=hcgdjor
    LONGOPTS=help,cpu,gpu,deepaas,jupyter,onedata,rclone
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

# if you try to start deepaas AND jupyterlab, only deepaas will start!
if [[ "$use_deepaas" = true && "$use_jupyter" = true ]]; then
   use_jupyter=false
   echo "[WARNING] You are trying to start DEEPaaS AND JupyterLab, only DEEPaaS will start!"
fi

# debugging printout
[[ "$debug_it" = true ]] && echo "[DEBUG] cpu: '$cpu_mode', gpu: '$gpu_mode', \
deepaas: '$use_deepaas', jupyter: '$use_jupyter', rclone: '$use_rclone', \
onedata: '$use_onedata'"

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
   check_env RCLONE_REMOTE_STORAGE $rclone_error
   [[ ! -v RCLONE_MOUNT_POINT || -z "${RCLONE_MOUNT_POINT}" ]] && RCLONE_MOUNT_POINT="/mnt/rclone"
   # check if local mount point exists
   if [ ! -d "$RCLONE_MOUNT_POINT" ]; then
      mkdir -p $RCLONE_MOUNT_POINT
   fi
   cmd="rclone mount --vfs-cache-mode full $RCLONE_REMOTE_STORAGE $RCLONE_MOUNT_POINT"
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
   [[ "$gpu_mode" = true ]] && DEEPaaS_PORT=$PORT0
   cmd="deepaas-run --openwhisk-detect --listen-ip=0.0.0.0 --listen-port=$DEEPaaS_PORT"
   echo "[DEEPaaS] $cmd"
   $cmd
   # we can't put process in the background, as the container will stop
fi

if [ "$use_jupyter" = true ]; then
   echo "[INFO] Attempt to start JupyterLab"
   Jupyter_PORT=8888
   [[ "$gpu_mode" = true ]] && Jupyter_PORT=$PORT2
   cmd="/srv/.deep-start/run_jupyter.sh --allow-root"
   echo "[Jupyter] jupyterPORT=$Jupyter_PORT, $cmd"
   export jupyterPORT=$Jupyter_PORT
   $cmd
   # we can't put process in the background, as the container will stop
fi
