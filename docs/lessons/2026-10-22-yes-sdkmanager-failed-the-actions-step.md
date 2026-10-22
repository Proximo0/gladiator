What happened: `yes | sdkmanager ...` failed the Actions step with exit 141 (bash runs with pipefail; `yes` dies of SIGPIPE)
Rule: `set +o pipefail` around it and check the installed file instead of the pipeline status
