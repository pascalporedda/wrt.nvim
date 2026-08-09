STYLUA ?= stylua
NVIM ?= nvim

# Optional picker backends. Point these at local checkouts to exercise the
# snacks and telescope adapters; without them the suite runs on core Neovim only.
DEPS := .tests
SNACKS := $(DEPS)/snacks.nvim
TELESCOPE := $(DEPS)/telescope.nvim
PLENARY := $(DEPS)/plenary.nvim

.PHONY: test test-bare test-all deps fmt lint clean

## Run the suite on core Neovim only (no picker plugins).
test-bare:
	$(NVIM) --headless -u tests/minimal_init.lua -c "luafile tests/run.lua"

## Run the suite with the optional picker backends.
test-all: deps
	WRT_TEST_SNACKS=$(abspath $(SNACKS)) \
	WRT_TEST_TELESCOPE=$(abspath $(TELESCOPE)) \
	WRT_TEST_PLENARY=$(abspath $(PLENARY)) \
	$(NVIM) --headless -u tests/minimal_init.lua -c "luafile tests/run.lua"

test: test-bare test-all

deps:
	@mkdir -p $(DEPS)
	@[ -d $(SNACKS) ] || git clone --filter=blob:none --depth 1 https://github.com/folke/snacks.nvim $(SNACKS)
	@[ -d $(TELESCOPE) ] || git clone --filter=blob:none --depth 1 https://github.com/nvim-telescope/telescope.nvim $(TELESCOPE)
	@[ -d $(PLENARY) ] || git clone --filter=blob:none --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY)

fmt:
	$(STYLUA) .

lint:
	$(STYLUA) --check .

clean:
	rm -rf $(DEPS)
