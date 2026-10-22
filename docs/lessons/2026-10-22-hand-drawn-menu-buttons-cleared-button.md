What happened: Hand-drawn menu buttons cleared `Button.text`, so `sim_net_quick_flow` (which reads panel buttons by their text) saw empty buttons
Rule: Custom-drawn buttons keep their plain label in `text` and hide it with transparent font colours; tests and logs read it
