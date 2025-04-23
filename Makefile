PACKER_DIR = ~/.local/share/nvim/site/pack/vendor/start

test:
	nvim --headless --noplugin -u lua/tests/minimal.vim -c "PlenaryBustedDirectory lua/tests/ {minimal_init = 'lua/tests/minimal.vim'}"
lint:
	luacheck lua/go
clean:
	rm -rf $(PACKER_DIR)

localtestsetup:
	@mkdir -p $(PACKER_DIR)
	@mkdir -p ~/tmp

	@test -d $(PACKER_DIR)/plenary.nvim ||\
		git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PACKER_DIR)/plenary.nvim

	@test -d $(PACKER_DIR)/guihua.lua ||\
		git clone --depth 1 https://github.com/ray-x/guihua.lua $(PACKER_DIR)/guihua.lua


	@test -d $(PACKER_DIR)/forgit.nvim || ln -s ${shell pwd} $(PACKER_DIR)

	nvim --headless -u lua/tests/minimal.vim -i NONE -c "TSUpdateSync go" -c "q"

