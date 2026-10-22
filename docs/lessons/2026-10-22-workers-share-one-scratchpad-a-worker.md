What happened: Workers share one scratchpad; a worker `rm -rf`'d a `before/` folder there that held another worker's captures
Rule: Keep scratch files under `scratchpad/<branch>/`; never delete a scratch path you did not create in this run
