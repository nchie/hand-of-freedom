# make app | install | run | test | clean. See README.
APP := build/Hand of Freedom.app
DEST := $(HOME)/Applications/Hand of Freedom.app

.PHONY: app install run test clean

app:
	Scripts/bundle.sh

# Quits a running copy, replaces the installed one, and launches it.
install: app
	-pkill -TERM -x HandOfFreedom && sleep 1
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(DEST)"
	cp -R "$(APP)" "$(DEST)"
	open -n "$(DEST)"

run: install

test:
	swift test

clean:
	rm -rf build .build
