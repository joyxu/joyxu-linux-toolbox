# SPDX-License-Identifier: GPL-2.0
#
# Makefile for relaxed_devmem kernel module (out-of-tree build)
#

# Kernel build directory
KDIR ?= /lib/modules/$(shell uname -r)/build

# Current directory
PWD := $(shell pwd)

# Module name
obj-m := relaxed_devmem.o

# Default target
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

# Clean target
clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean

# Install target
install:
	$(MAKE) -C $(KDIR) M=$(PWD) modules_install

# Uninstall target
uninstall:
	rm -f /lib/modules/$(shell uname -r)/extra/relaxed_devmem.ko
	depmod -a

.PHONY: all clean install uninstall
