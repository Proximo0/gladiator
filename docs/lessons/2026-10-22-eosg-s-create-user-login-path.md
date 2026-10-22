What happened: EOSG's create-user login path fires no Connect login callback, so the runtime never learned the local user
Rule: Log in a second time after creating the device user; mock a plugin's native singleton to run its real GDScript without the binaries
