What happened: Closing the ENet peer from inside its own `poll()` (a disconnect signal handler) crashed with signal 11
Rule: Never close a MultiplayerPeer from its own signal; defer the close to the next idle frame
