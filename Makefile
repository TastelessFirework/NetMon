.PHONY: build release test app icon install package

INSTALL_DIR ?= $(HOME)/Applications

build:
	./Scripts/build.sh build debug

release:
	./Scripts/build.sh build release

test:
	./Scripts/build.sh test

app:
	./Scripts/build.sh app

icon:
	./Scripts/build.sh icon

install: app
	mkdir -p "$(INSTALL_DIR)"
	ditto "dist/NetMon.app" "$(INSTALL_DIR)/NetMon.app"
	@echo "Installed $(INSTALL_DIR)/NetMon.app"

package:
	./Scripts/package.sh
