// SPDX-License-Identifier: GPL-2.0-only
/**
 * PCIe BAR Read Benchmark Tool (Relaxed devmem version)
 *
 * This tool benchmarks read performance from PCIe BAR (Base Address Register) space
 * using /dev/relaxed_devmem, which allows access to PCIe MMIO space even when
 * CONFIG_STRICT_DEVMEM is enabled.
 *
 * Usage: sudo ./pcibar_bench_relaxed -d <domain> -b <bus> -D <device> -f <function> -B <bar> -i <iterations> -s <block_size>
 *
 * Requirements:
 * - Root privileges
 * - relaxed_devmem kernel module loaded
 * - Target PCI device with BAR space
 */

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

#define MAX_PATH 256
#define RELAXED_DEVMEM_PATH "/dev/relaxed_devmem"

struct pci_bar_info {
	unsigned long long base_addr;
	unsigned long long size;
	unsigned int bar_num;
	char sysfs_path[MAX_PATH];
};

static int get_pci_bar_info(unsigned int domain, unsigned int bus,
			    unsigned int dev, unsigned int func,
			    unsigned int bar_num,
			    struct pci_bar_info *info)
{
	char path[MAX_PATH];
	FILE *fp;
	char line[256];
	unsigned long long start, end, flags;

	snprintf(path, sizeof(path),
		 "/sys/bus/pci/devices/%04x:%02x:%02x.%x/resource",
		 domain, bus, dev, func);

	fp = fopen(path, "r");
	if (!fp) {
		perror("Failed to open resource file");
		return -1;
	}

	info->bar_num = bar_num;
	strncpy(info->sysfs_path, path, MAX_PATH);

	for (int i = 0; i <= bar_num; i++) {
		if (fgets(line, sizeof(line), fp) == NULL) {
			fprintf(stderr, "Failed to read BAR%d info\n", bar_num);
			fclose(fp);
			return -1;
		}
	}

	fclose(fp);

	if (sscanf(line, "0x%llx 0x%llx 0x%llx", &start, &end, &flags) != 3) {
		fprintf(stderr, "Failed to parse BAR%d info\n", bar_num);
		return -1;
	}

	if (start == 0) {
		fprintf(stderr, "BAR%d not implemented\n", bar_num);
		return -1;
	}

	info->base_addr = start;
	info->size = end - start + 1;

	printf("BAR%d: base=0x%llx, size=0x%llx (%llu KB)\n",
	       bar_num, info->base_addr, info->size,
	       info->size / 1024);

	return 0;
}

static double get_time_ms(void)
{
	struct timeval tv;

	gettimeofday(&tv, NULL);
	return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0;
}

static void benchmark_read(volatile void *bar_base, unsigned long bar_size,
			   unsigned int iterations, unsigned int block_size,
			   unsigned long bytes_per_iteration)
{
	unsigned long long total_bytes = 0;
	double start_time, end_time;
	unsigned int i;
	unsigned char *buffer;
	volatile unsigned char *ptr;

	buffer = malloc(block_size);
	if (!buffer) {
		perror("Failed to allocate buffer");
		return;
	}

	printf("\nBenchmarking read operations:\n");
	printf("Iterations: %u\n", iterations);
	printf("Block size: %u bytes\n", block_size);
	printf("Bytes per iteration: %lu bytes\n", bytes_per_iteration);
	printf("BAR size: %lu bytes\n", bar_size);

	start_time = get_time_ms();

	for (i = 0; i < iterations; i++) {
		ptr = (volatile unsigned char *)bar_base;
		unsigned long offset = 0;
		unsigned long bytes_read_this_iter = 0;

		while (offset + block_size <= bar_size && bytes_read_this_iter < bytes_per_iteration) {
			for (unsigned int j = 0; j < block_size; j++) {
				buffer[j] = ptr[offset + j];
			}
			offset += block_size;
			bytes_read_this_iter += block_size;
			total_bytes += block_size;
		}
	}

	end_time = get_time_ms();

	double elapsed_ms = end_time - start_time;
	double throughput_mbps = (total_bytes / (1024.0 * 1024.0)) / (elapsed_ms / 1000.0);
	double ops_per_sec = (double)iterations / (elapsed_ms / 1000.0);

	printf("\nResults:\n");
	printf("Total bytes read: %llu MB\n", total_bytes / (1024 * 1024));
	printf("Elapsed time: %.2f ms\n", elapsed_ms);
	printf("Throughput: %.2f MB/s\n", throughput_mbps);
	printf("Operations: %.2f ops/sec\n", ops_per_sec);

	free(buffer);
}

static void benchmark_read_random(volatile void *bar_base, unsigned long bar_size,
				  unsigned int iterations, unsigned int block_size,
				  unsigned long bytes_per_iteration)
{
	unsigned long long total_bytes = 0;
	double start_time, end_time;
	unsigned int i;
	unsigned char *buffer;
	unsigned int seed = 12345;

	buffer = malloc(block_size);
	if (!buffer) {
		perror("Failed to allocate buffer");
		return;
	}

	printf("\nBenchmarking random read operations:\n");
	printf("Iterations: %u\n", iterations);
	printf("Block size: %u bytes\n", block_size);
	printf("Bytes per iteration: %lu bytes\n", bytes_per_iteration);
	printf("BAR size: %lu bytes\n", bar_size);

	start_time = get_time_ms();

	for (i = 0; i < iterations; i++) {
		unsigned long bytes_read_this_iter = 0;

		while (bytes_read_this_iter < bytes_per_iteration) {
			unsigned long offset = (rand_r(&seed) % (bar_size / block_size)) * block_size;
			volatile unsigned char *ptr = (volatile unsigned char *)bar_base + offset;

			for (unsigned int j = 0; j < block_size; j++) {
				buffer[j] = ptr[j];
			}
			bytes_read_this_iter += block_size;
			total_bytes += block_size;
		}
	}

	end_time = get_time_ms();

	double elapsed_ms = end_time - start_time;
	double throughput_mbps = (total_bytes / (1024.0 * 1024.0)) / (elapsed_ms / 1000.0);
	double ops_per_sec = (double)iterations / (elapsed_ms / 1000.0);

	printf("\nResults:\n");
	printf("Total bytes read: %llu MB\n", total_bytes / (1024 * 1024));
	printf("Elapsed time: %.2f ms\n", elapsed_ms);
	printf("Throughput: %.2f MB/s\n", throughput_mbps);
	printf("Operations: %.2f ops/sec\n", ops_per_sec);

	free(buffer);
}

int main(int argc, char **argv)
{
	int mem_fd;
	void *mapped_bar;
	struct pci_bar_info bar_info;
	unsigned int domain = 0, bus = 0, dev = 0, func = 0;
	unsigned int bar_num = 0;
	unsigned int iterations = 1000;
	unsigned int block_size = 64;
	unsigned long bytes_per_iteration = 0;
	int random_access = 0;
	int c;

	if (argc < 2) {
		fprintf(stderr,
			"Usage: %s [options]\n"
			"Options:\n"
			"\t-d <domain>	PCI domain (default: 0)\n"
			"\t-b <bus>	PCI bus number (default: 0)\n"
			"\t-D <device>	PCI device number (default: 0)\n"
			"\t-f <function>	PCI function number (default: 0)\n"
			"\t-B <bar>	BAR number (default: 0)\n"
			"\t-i <iter>	Number of (default: 1000)\n"
			"\t-s <size>	Block size in bytes (default: 64)\n"
			"\t-n <bytes>	Bytes per iteration (default: BAR size)\n"
			"\t-r		Random access pattern\n"
			"\t-h		Print this help message\n"
			"\nExample:\n"
			"\t%s -b 81 -D 00 -f 0 -B 0 -i 10000 -s 256 -n 4096\n",
			argv[0], argv[0]);
		return 1;
	}

	while ((c = getopt(argc, argv, "d:b:D:f:B:i:s:n:rh")) != EOF) {
		switch (c) {
		case 'd':
			domain = strtoul(optarg, NULL, 0);
			break;
		case 'b':
			bus = strtoul(optarg, NULL, 0);
			break;
		case 'D':
			dev = strtoul(optarg, NULL, 0);
			break;
		case 'f':
			func = strtoul(optarg, NULL, 0);
			break;
		case 'B':
			bar_num = strtoul(optarg, NULL, 0);
			if (bar_num > 5) {
				fprintf(stderr, "Invalid BAR number: %u\n", bar_num);
				return 1;
			}
			break;
		case 'i':
			iterations = strtoul(optarg, NULL, 0);
			break;
		case 's':
			block_size = strtoul(optarg, NULL, 0);
			break;
		case 'n':
			bytes_per_iteration = strtoul(optarg, NULL, 0);
			break;
		case 'r':
			random_access = 1;
			break;
		case 'h':
		default:
			fprintf(stderr,
				"Usage: %s [options]\n"
				"Options:\n"
				"\t-d <domain>	PCI domain (default: 0)\n"
				"\t-b <bus>	PCI bus number (default: 0)\n"
				"\t-D <device>	PCI device number (default: 0)\n"
				"\t-f <function>	PCI function number (default: 0)\n"
				"\t-B <bar>	BAR number (default: 0)\n"
				"\t-i <iter>	Number of iterations (default: 1000)\n"
				"\t-s <size>	Block size in bytes (default: 64)\n"
				"\t-n <bytes>	Bytes per iteration (default: BAR size)\n"
				"\t-r		Random access pattern\n"
				"\t-h		Print this help message\n",
				argv[0]);
			return 1;
		}
	}

	printf("PCIe BAR Read Benchmark (Relaxed devmem version)\n");
	printf("================================================\n");
	printf("PCI Device: %04x:%02x:%02x.%x\n", domain, bus, dev, func);

	if (get_pci_bar_info(domain, bus, dev, func, bar_num, &bar_info) < 0) {
		return 1;
	}

	if (bytes_per_iteration == 0 || bytes_per_iteration > bar_info.size) {
		bytes_per_iteration = bar_info.size;
		printf("Setting bytes per iteration to BAR size: %lu bytes\n", bytes_per_iteration);
	}

	mem_fd = open(RELAXED_DEVMEM_PATH, O_RDWR | O_SYNC);
	if (mem_fd < 0) {
		perror("Failed to open " RELAXED_DEVMEM_PATH);
		fprintf(stderr, "Make sure you have root privileges and relaxed_devmem module is loaded\n");
		return 1;
	}

	mapped_bar = mmap(NULL, bar_info.size, PROT_READ, MAP_SHARED,
			  mem_fd, bar_info.base_addr);
	if (mapped_bar == MAP_FAILED) {
		perror("Failed to mmap BAR space");
		close(mem_fd);
		return 1;
	}

	if (random_access) {
		benchmark_read_random(mapped_bar, bar_info.size, iterations, block_size, bytes_per_iteration);
	} else {
		benchmark_read(mapped_bar, bar_info.size, iterations, block_size, bytes_per_iteration);
	}

	mem_fd = open(RELAXED_DEVMEM_PATH, O_RDWR | O_SYNC);
	if (mem_fd < 0) {
		perror("Failed to open " RELAXED_DEVMEM_PATH);
		fprintf(stderr, "Make sure you have root privileges and the relaxed_devmem module is loaded\n");
		return 1;
	}

	mapped_bar = mmap(NULL, bar_info.size, PROT_READ, MAP_SHARED,
			  mem_fd, bar_info.base_addr);
	if (mapped_bar == MAP_FAILED) {
		perror("Failed to mmap BAR space");
		close(mem_fd);
		return 1;
	}

	if (random_access) {
		benchmark_read_random(mapped_bar, bar_info.size, iterations, block_size, bytes_per_iteration);
	} else {
		benchmark_read(mapped_bar, bar_info.size, iterations, block_size, bytes_per_iteration);
	}

	munmap(mapped_bar, bar_info.size);
	close(mem_fd);

	return 0;
}
