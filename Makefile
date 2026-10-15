# xeneonctl - builds on macOS (Apple Silicon) and Windows with the same
# commands. The platform is detected automatically; see src/xeneonctl.m
# (macOS, IOAVService) and src/xeneonctl.c (Windows, Dxva2).

ifeq ($(OS),Windows_NT)
    PLATFORM := windows
else
    PLATFORM := $(shell uname -s)
endif

ifeq ($(PLATFORM),windows)

NAME     = xeneonctl.exe
SRC      = src/xeneonctl.c
CC       = gcc
CFLAGS   = -Wall -Wextra -O2
LDLIBS   = -ldxva2 -luser32
# %LOCALAPPDATA% comes through with backslashes; make and sh both prefer
# forward slashes, and the Windows APIs accept them either way.
BIN_DIR  = $(subst \,/,$(LOCALAPPDATA))/Programs/xeneonctl
SUDO     =
GUI_RUN  = dotnet run --project gui-windows

else ifeq ($(PLATFORM),Darwin)

NAME     = xeneonctl
SRC      = src/xeneonctl.m
CC       = clang
CFLAGS   = -Wall -Wextra -fmodules -fobjc-arc
LDLIBS   = -framework CoreDisplay -framework IOKit -framework Foundation -framework CoreGraphics
BIN_DIR  = /usr/local/bin
SUDO     = sudo
GUI_RUN  = swift run --package-path gui

else

$(error Unsupported platform '$(PLATFORM)'. xeneonctl supports macOS (Apple Silicon) and Windows.)

endif

WAKEFIX_NAME  = xeneon-wakefix
WAKEFIX_BIN   = wakefix/.build/release/XeneonWakeFix
WAKEFIX_LABEL = com.xeneonctl.wakefix
WAKEFIX_PLIST = $(HOME)/Library/LaunchAgents/$(WAKEFIX_LABEL).plist

.PHONY: all install uninstall clean gui wakefix install-wakefix uninstall-wakefix

all: $(NAME)

$(NAME): $(SRC)
	$(CC) $(CFLAGS) $< -o $@ $(LDLIBS)

ifeq ($(PLATFORM),windows)

# No permission bits to set, and lighter toolchains (w64devkit) ship
# without install(1), so keep this to mkdir + cp.
install: $(NAME)
	mkdir -p "$(BIN_DIR)"
	cp $(NAME) "$(BIN_DIR)/$(NAME)"
	@echo "Installed to $(BIN_DIR)"
	@echo "Add that folder to your PATH to run 'xeneonctl' from anywhere."

else

install: $(NAME)
	$(SUDO) install -d "$(BIN_DIR)"
	$(SUDO) install -m 0755 $(NAME) "$(BIN_DIR)/$(NAME)"

endif

uninstall:
	$(SUDO) rm -f "$(BIN_DIR)/$(NAME)"

clean:
	rm -f $(NAME)

# Small slider window that shells out to the CLI above, so build that first.
gui: $(NAME)
	$(GUI_RUN)

# Optional: background helper that clears the Xeneon Edge's known
# "stuck touch" state on wake from sleep. See wakefix/README.md.
ifeq ($(PLATFORM),Darwin)

wakefix:
	swift build -c release --package-path wakefix

install-wakefix: wakefix
	sudo install -m 0755 $(WAKEFIX_BIN) $(BIN_DIR)/$(WAKEFIX_NAME)
	mkdir -p $(HOME)/Library/LaunchAgents
	install -m 0644 wakefix/$(WAKEFIX_LABEL).plist $(WAKEFIX_PLIST)
	launchctl bootstrap gui/$$(id -u) $(WAKEFIX_PLIST) 2>/dev/null || launchctl load $(WAKEFIX_PLIST)
	@echo "Installed. macOS will prompt for Accessibility access the first time it runs (System Settings > Privacy & Security > Accessibility) - approve $(WAKEFIX_NAME) so it can clear the stuck touch state."

uninstall-wakefix:
	-launchctl bootout gui/$$(id -u)/$(WAKEFIX_LABEL) 2>/dev/null || launchctl unload $(WAKEFIX_PLIST) 2>/dev/null
	rm -f $(WAKEFIX_PLIST)
	sudo rm -f $(BIN_DIR)/$(WAKEFIX_NAME)

else

wakefix install-wakefix uninstall-wakefix:
	@echo "The wake fix is macOS-only - it works around an Apple-specific sleep/wake quirk."

endif
