What happened: The finisher slow motion's first frame ran the camera and effects five times too far: the frame's delta was scaled by the old time scale, but `real_delta` divided by the new one that physics had just set
Rule: Divide a frame's delta by the time scale in force when the frame began (`RealClock`); a scale change inside physics applies from the next frame
