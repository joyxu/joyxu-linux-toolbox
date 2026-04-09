# Makefile for pcibar_bench_relaxed userspace application

CC = gcc
CFLAGS = -O2 -Wall -g -D_GNU_SOURCE
TARGET = pcibar_bench_relaxed
SOURCE = pcibar_bench_relaxed.c

# Default target
all: $(TARGET)

# Build the application
$(TARGET): $(SOURCE)
	$(CC) $(CFLAGS) $(SOURCE) -o $(TARGET)

# Clean target
clean:
	rm -f $(TARGET)

# Install target
install: $(TARGET)
	install -d -m 755 $(DESTDIR)/usr/bin
	install -m 755 $(TARGET) $(DESTDIR)/usr/bin/

# Uninstall target
uninstall:
	rm -f $(DESTDIR)/usr/bin/$(TARGET)

.PHONY: all clean install uninstall
