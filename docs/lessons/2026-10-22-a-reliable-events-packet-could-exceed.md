What happened: A reliable events packet could exceed the EOS relay's 1164-byte limit and be silently dropped
Rule: Split network packets by bytes, not by record count (`NetEvents.encode_chunks`)
