Start script(s) for DEEP containers
==================================

deep-start.sh
-------------

**Main start script** for DEEP containers. Automatically detects if NVIDIA-GPU is present in the system.
Default start is equivalent to ``deep-start.sh -d``.

Usage: deep-start.sh <options> 

    Options:
    -h|--help 		 the help message
    -c|--cpu 		 force CPU-only execuition (otherwise detected automatically)
    -g|--gpu 		 force GPU execution mode  (otherwise detected automatically)
    -d|--deepaas 	 start deepaas-run
    -j|--jupyter 	 start JupyterLab, if installed
    -o|--onedata 	 mount remote storage usinge oneclient
    -r|--rclone  	 mount remote storage with rclone (experimental!)

NOTE: if you try to start deepaas AND jupyterlab, only deepaas will start!

run_jupyter.sh
--------------
Script to start jupyterlab, also checks jupyterCONFIG_URL environment for more advanced configuration (e.g. download of certificates)

jupyter_notebook_config.py
--------------------------
Module to set Jupyter access password from the jupyterPASSWORD environment, if available.
BASED ON: https://github.com/tensorflow/tensorflow/blob/master/tensorflow/tools/docker/jupyter_notebook_config.py