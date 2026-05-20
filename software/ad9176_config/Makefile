# Makefile -- ad9176-config user-space tool
#
# Targets:
#   make            -- host build (gcc) for syntax/sanity; not deployable
#   make CROSS=...  -- cross-compile for the dev kit HPS
#                      (e.g. CROSS=aarch64-linux-gnu-)
#   make clean
#
# The host build is a smoke test; it links against the same .c sources but
# the resulting binary will fail at /dev/mem open unless run on the dev
# kit. Use the host build to catch warnings before flashing.

CROSS    ?=
CC       := $(CROSS)gcc
CFLAGS   ?= -O2 -Wall -Wextra -Wpedantic -Werror -std=c11
LDFLAGS  ?=

# Avoid -Werror on the host build's mmap-cast diagnostic; keep it strict
# on cross builds where the toolchain matches the target.
ifeq ($(CROSS),)
CFLAGS += -Wno-unused-parameter
endif

SRCS    := ad9176_config.c ad9176_fmc_ebz.c ad9176_init.c
OBJS    := $(SRCS:.c=.o)
TARGET  := ad9176-config

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $@ $(OBJS) $(LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJS) $(TARGET)
