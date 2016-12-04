#!/usr/bin/env lua5.3
require "../lib/usock"
if (#arg < 1) then
	print("Argument needed, like '/containers/json'")
	os.exit(1)
end

h, b = unixHttp.request(arg[1])
print(b)
