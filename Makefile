NAME     = xeneonctl
SRC      = src/xeneonctl.m
CC       = clang
CFLAGS   = -Wall -Wextra -fmodules -fobjc-arc
LDLIBS   = -framework CoreDisplay -framework IOKit -framework Foundation -framework CoreGraphics
BIN_DIR  = /usr/local/bin

.PHONY: all install uninstall clean

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
