#!/usr/bin/env bash
# This script allows to pass optional parameters during 
# JupyterLab startup without changing the container command

if [[ ! -v jupyterOPTS ]]; then
    jupyterOPTS=""
fi

# mainly for debugging:
echo "[run_jupyter] script_path: $SCRIPT_PATH, opts: $jupyterOPTS"

# activate "Quit" button: do not do this, server shuts down!
#jupyter lab --LabApp.quit_button=True $jupyterOPTS "$@"

jupyter lab $jupyterOPTS "$@"
