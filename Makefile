test: build
	busted

build:
	luarocks make rockspecs/jmespath-0.1-0.rockspec > /dev/null

perf: build
	@if [ -n "$$JIT" ]; then luajit perf.lua; else lua perf.lua; fi

test-setup:
	luarocks install busted
	luarocks install luafilesystem

.PHONY: build
