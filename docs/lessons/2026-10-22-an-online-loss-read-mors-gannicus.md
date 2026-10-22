What happened: An online loss read "MORS / Gannicus wins": online matches take their fighter names from the seed, not from the lobby, and a unit test leaked a never-freed `OnlineService` node
Rule: Name the opponent from the service or session on online panels; free every Node a unit test makes (a leak warning ends the whole test run)
