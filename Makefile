NAME     = xeneonctl
SRC      = src/xeneonctl.m
CC       = clang
CFLAGS   = -Wall -Wextra -fmodules -fobjc-arc
LDLIBS   = -framework CoreDisplay -framework IOKit -framework Foundation -framework CoreGraphics
BIN_DIR  = /usr/local/bin

WAKEFIX_NAME  = xeneon-wakefix
WAKEFIX_BIN   = wakefix/.build/release/XeneonWakeFix
WAKEFIX_LABEL = com.xeneonctl.wakefix
WAKEFIX_PLIST = $(HOME)/Library/LaunchAgents/$(WAKEFIX_LABEL).plist

.PHONY: all install uninstall clean wakefix install-wakefix uninstall-wakefix

all: $(NAME)

$(NAME): $(SRC)
	$(CC) $(CFLAGS) $(LDLIBS) $< -o $@

install: $(NAME)
	install -d $(BIN_DIR)
	sudo install -m 0755 $(NAME) $(BIN_DIR)/$(NAME)

uninstall:
	sudo rm -f $(BIN_DIR)/$(NAME)

clean:
	rm -f $(NAME)

# Optional: background helper that clears the Xeneon Edge's known
# "stuck touch" state on wake from sleep. See wakefix/README.md.
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
