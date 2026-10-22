What happened: The instant replay paused the online driver, and 5 s without packets (`DISCONNECT_TICKS`) ended the session
Rule: Anything that pauses a net driver keeps the session alive (KillCam sends a one-byte packet a few times a second)
