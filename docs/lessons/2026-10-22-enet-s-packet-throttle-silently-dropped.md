What happened: ENet's packet throttle silently dropped about half the unreliable snapshots after a frame hitch
Rule: Switch the ENet throttle off on connect (deceleration 0) for snapshot streams
