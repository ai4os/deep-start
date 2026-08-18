Start script(s) for DEEP/AI4OS containers
==================================

deep-start
-----------

The **main start script** for DEEP/AI4OS containers. Automatically detects if NVIDIA-GPU is present in the system.
Default start is equivalent to ``deep-start -d``.

Usage: deep-start <options> 

    Options:
    -h|--help         the help message
    -c|--cpu          force CPU-only execuition (otherwise detected automatically)
    -g|--gpu          force GPU execution mode (otherwise detected automatically)
    -d|--deepaas      start deepaas-run
    -i|--install      enforce that the latest git repo of the deep-start script is installed
    -j|--jupyter      start JupyterLab; if not installed, will be automatically installed
    -o|--opencode     start OpenCode; if not installed, will be automatically installed
    --onedata         mount remote storage using oneclient
    -s|--vscode       start VSCode (code-server); if not installed, will be automatically installed
    -v|--version      print script version and exit
NOTE: if you try to start deepaas-run AND jupyterlab or vscode or opencode, only deepaas-run will start!


jupyter_notebook_config.py
--------------------------
(and symlink jupyter_server_config.py)

Module to set Jupyter access password from the jupyterPASSWORD environment, if available. Tested for jupyterlab v2,3,4.
In addition it provides default settings for JupyterLab, e.g.:
* --ip
* --port
* --no-browser
* --allow-root

(directory) lab
----------------
contains very basic configuration for Jupyter Lab

(directory) vscode
-------------------
contains very basic configuration for VSCode

ide-extensions.ini
-------------------
`ide-extensions.ini` is the shared manifest for IDE add-ons:

* `[vscode]`: Open VSX extension IDs installed by code-server.
* `[jupyterlab]`: PyPI requirements for prebuilt JupyterLab extensions, installed with `pip3`.
* `[opencode]`: reserved for future OpenCode add-ons; its current configuration is `opencode/opencode.jsonc`.

During execution of `deep-start`, the manifest from GitHub is preferred, with the local manifest used if it cannot be fetched.

`vscode/code-server/vscode-extensions.txt` remains in the repository for compatibility with versions **below v3.0.0** but is deprecated.


!! Depricated
------------
run_jupyter.sh : script to start jupyterlab =>> now deep-start starts jupyterlab directly
