#!/bin/bash
# Build script for pcibar_benchmark

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== PCIe BAR Benchmark Build Script ==="
echo ""

# Check if running as root for module operations
if [ "$EUID" -eq 0 ]; then
    echo "Warning: Running as root. This is not recommended for building."
    echo "Only use root for loading/unloading module."
    echo ""
fi

# Parse command line arguments
ACTION=${1:-all}

case "$ACTION" in
    all)
        echo "Building kernel module..."
        cd relaxed_devmem
        make clean
        make

        cd ..

        echo ""
        echo "Building userspace application..."
        make clean
        make

        echo ""
        echo "=== Build Complete ==="
        echo "Kernel module: relaxed_devmem/relaxed_devmem.ko"
        echo "Userspace app: pcibar_bench_relaxed"
        echo ""
        echo "To use:"
        echo "  sudo insmod relaxed_devmem/relaxed_devmem.ko"
        echo "  sudo ./pcibar_bench_relaxed [options]"
        echo "  sudo rmmod relaxed_devmem"
        ;;

    module)
        echo "Building kernel module..."
        cd relaxed_devmem
        make clean
        make
        echo ""
        echo "Kernel module built: relaxed_devmem/relaxed_devmem.ko"
        ;;

    app)
        echo "Building userspace application..."
        make clean
        make
        echo ""
        echo "Userspace app built: pcibar_bench_relaxed"
        ;;

    clean)
        echo "Cleaning all builds..."
        cd relaxed_devmem
        make clean
        cd ..
        make clean
        echo ""
        echo "Clean complete"
        ;;

    load)
        if [ "$EUID" -ne 0 ]; then
            echo "Error: This command requires root privileges"
            echo "Please run with: sudo $0 load"
            exit 1
        fi

        echo "Loading kernel module..."
        if lsmod | grep -q relaxed_devmem; then
            echo "Module already loaded, reloading..."
            rmmod relaxed_devmem
        fi
        insmod relaxed_devmem/relaxed_devmem.ko
        echo "Module loaded successfully"
        echo "Device created: /dev/relaxed_devmem"
        ;;

    unload)
        if [ "$EUID" -ne 0 ]; then
            echo "Error: This command requires root privileges"
            echo "Please run with: sudo $0 unload"
            exit 1
        fi

        echo "Unloading kernel module..."
        if lsmod | grep -q relaxed_devmem; then
            rmmod relaxed_devmem
            echo "Module unloaded successfully"
        else
            echo "Module not loaded"
        fi
        ;;

    test)
        if [ "$EUID" -ne 0 ]; then
            echo "Error: This command requires root privileges"
            echo "Please run with: sudo $0 test"
            exit 1
        fi

        echo "Running quick test..."
        if ! lsmod | grep -q relaxed_devmem; then
            echo "Loading module..."
            insmod relaxed_devmem/relaxed_devmem.ko
        fi

        echo ""
        echo "Testing with DMA engine device (7b:00.0 BAR2)..."
        ./pcibar_bench_relaxed -d 0x0 -b 0x7b -D 0x00 -f 0x0 -B 0x2 -i 10 -s 64 -n 4096

        echo ""
        echo "Test complete"
        ;;

    *)
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  all     - Build kernel module and userspace app (default)"
        echo "  module  - Build kernel module only"
        echo "  app     - Build userspace app only"
        echo "  clean   - Clean all build artifacts"
        echo "  load    - Load kernel module (requires root)"
        echo "  unload  - Unload kernel module (requires root)"
        echo "  test    - Run quick benchmark test (requires root)"
        echo ""
        echo "Examples:"
        echo "  $0           # Build everything"
        echo "  sudo $0 load  # Load module"
        echo "  sudo $0 test  # Run test"
        echo "  sudo $0 unload # Unload module"
        exit 1
        ;;
esac
