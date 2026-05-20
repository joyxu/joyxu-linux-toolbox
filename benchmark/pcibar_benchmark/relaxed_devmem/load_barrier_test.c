#include <stdio.h>
#include <stdint.h>

#define ITERATIONS 1000000

volatile uint64_t shared_data = 0;
volatile uint64_t flag = 0;

static inline uint64_t load_normal(volatile uint64_t *addr)
{
	uint64_t val;
	asm volatile("ldr %0, [%1]" : "=r"(val) : "r"(addr) : "memory");
	return val;
}

static inline uint64_t load_acquire(volatile uint64_t *addr)
{
	uint64_t val;
	asm volatile("ldar %0, [%1]" : "=r"(val) : "r"(addr) : "memory");
	return val;
}

static inline uint64_t get_cycles(void)
{
	uint64_t val;
	asm volatile("isb" ::: "memory");
	asm volatile("mrs %0, cntvct_el0" : "=r"(val));
	asm volatile("isb" ::: "memory");
	return val;
}

static double measure_normal_load(void)
{
	volatile uint64_t data = 0x12345678;
	uint64_t start, end;
	uint64_t sum = 0;

	start = get_cycles();
	for (int i = 0; i < ITERATIONS; i++) {
		sum += load_normal(&data);
	}
	end = get_cycles();

	return (double)(end - start) / ITERATIONS;
}

static double measure_acquire_load(void)
{
	volatile uint64_t data = 0x12345678;
	uint64_t start, end;
	uint64_t sum = 0;

	start = get_cycles();
	for (int i = 0; i < ITERATIONS; i++) {
		sum += load_acquire(&data);
	}
	end = get_cycles();

	return (double)(end - start) / ITERATIONS;
}

static double measure_mixed_load(void)
{
	volatile uint64_t data = 0x12345678;
	uint64_t start, end;
	uint64_t sum = 0;

	start = get_cycles();
	for (int i = 0; i < ITERATIONS; i++) {
		sum += load_normal(&data);
		sum += load_acquire(&data);
		sum += load_normal(&data);
		sum += load_acquire(&data);
	}
	end = get_cycles();

	return (double)(end - start) / (ITERATIONS * 4);
}

int main(int argc, char *argv[])
{
	printf("=== ARM64 Load Barrier Test ===\n\n");

	printf("1. Performance Test (cycles per load):\n");
	printf("   Normal LDR:     %.2f cycles\n", measure_normal_load());
	printf("   LDAR (acquire): %.2f cycles\n", measure_acquire_load());
	printf("   Mixed pattern: %.2f cycles\n", measure_mixed_load());

	printf("\n2. Cache Line Analysis (load only):\n");
	volatile uint64_t data[8] __attribute__((aligned(64)));
	uint64_t start, end;

	for (int i = 0; i < 8; i++) {
		data[i] = i;
	}

	start = get_cycles();
	for (int i = 0; i < ITERATIONS; i++) {
		asm volatile("ldr x0, [%0, #0]\n\t"
			     "ldar x1, [%1]\n\t"
			     "ldr x2, [%0, #16]\n\t"
			     "ldar x3, [%2]\n\t"
			     "ldr x4, [%0, #32]\n\t"
			     "ldar x5, [%3]\n\t"
			     "ldr x6, [%0, #48]\n\t"
			     "ldar x7, [%4]"
			     :
			     : "r"(data), "r"(&data[1]), "r"(&data[3]), "r"(&data[5]), "r"(&data[7])
			     : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "memory");
	}
	end = get_cycles();

	printf("   Mixed load on same cache line: %.2f cycles total\n",
	       (double)(end - start) / ITERATIONS);

	printf("\n3. Mixed Load/Store Test:\n");
	start = get_cycles();
	for (int i = 0; i < ITERATIONS; i++) {
		asm volatile("ldr x0, [%0, #0]\n\t"
			     "str x0, [%0, #8]\n\t"
			     "ldar x1, [%1]\n\t"
			     "stlr x1, [%2]\n\t"
			     "ldr x2, [%0, #16]\n\t"
			     "str x2, [%0, #24]\n\t"
			     "ldar x3, [%3]\n\t"
			     "stlr x3, [%4]\n\t"
			     "ldr x4, [%0, #32]\n\t"
			     "str x4, [%0, #40]\n\t"
			     "ldar x5, [%5]\n\t"
			     "stlr x5, [%6]\n\t"
			     "ldr x6, [%0, #48]\n\t"
			     "str x6, [%0, #56]\n\t"
			     "ldar x7, [%7]\n\t"
			     "stlr x7, [%8]"
			     :
			     : "r"(data), "r"(&data[1]), "r"(&data[2]), "r"(&data[3]), "r"(&data[4]),
			       "r"(&data[5]), "r"(&data[6]), "r"(&data[7]), "r"(&data[0])
			     : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "memory");
	}
	end = get_cycles();

	printf("   Mixed load/store (8 ldr+str + 8 ldar+stlr): %.2f cycles total\n",
	       (double)(end - start) / ITERATIONS);

	printf("\n4. Sequential Write Test:\n");
	start = get_cycles();
	for (int i = 0; i < ITERATIONS; i++) {
		asm volatile("mov x0, #1\n\t"
			     "str x0, [%0, #0]\n\t"
			     "mov x1, #2\n\t"
			     "str x1, [%0, #8]\n\t"
			     "mov x2, #3\n\t"
			     "str x2, [%0, #16]\n\t"
			     "mov x3, #4\n\t"
			     "str x3, [%0, #24]\n\t"
			     "mov x4, #5\n\t"
			     "str x4, [%0, #32]\n\t"
			     "mov x5, #6\n\t"
			     "str x5, [%0, #40]\n\t"
			     "mov x6, #7\n\t"
			     "str x6, [%0, #48]\n\t"
			     "mov x7, #8\n\t"
			     "str x7, [%0, #56]"
			     :
			     : "r"(data)
			     : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "memory");
	}
	end = get_cycles();

	printf("   Normal STR (8 stores): %.2f cycles total\n",
	       (double)(end - start) / ITERATIONS);

	start = get_cycles();
	for (int i = 0; i < ITERATIONS; i++) {
		asm volatile("mov x0, #1\n\t"
			     "stlr x0, [%0]\n\t"
			     "mov x1, #2\n\t"
			     "stlr x1, [%1]\n\t"
			     "mov x2, #3\n\t"
			     "stlr x2, [%2]\n\t"
			     "mov x3, #4\n\t"
			     "stlr x3, [%3]\n\t"
			     "mov x4, #5\n\t"
			     "stlr x4, [%4]\n\t"
			     "mov x5, #6\n\t"
			     "stlr x5, [%5]\n\t"
			     "mov x6, #7\n\t"
			     "stlr x6, [%6]\n\t"
			     "mov x7, #8\n\t"
			     "stlr x7, [%7]"
			     :
			     : "r"(&data[0]), "r"(&data[1]), "r"(&data[2]), "r"(&data[3]),
			       "r"(&data[4]), "r"(&data[5]), "r"(&data[6]), "r"(&data[7])
			     : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "memory");
	}
	end = get_cycles();

	printf("   Release STLR (8 stores): %.2f cycles total\n",
	       (double)(end - start) / ITERATIONS);

	return 0;
}