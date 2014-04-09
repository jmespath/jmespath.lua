test: build
	busted

build:
	@luarocks make > /dev/null

perf: build
	@if [ -n "$$JIT" ]; then luajit perf.lua; else lua perf.lua; fi

test-setup:
	luarocks install busted
	luarocks install luafilesystem
