//----------------------------------------------------------------------------
//
// Arm64 CPU SVE capability check
//
//----------------------------------------------------------------------------

#include <stdio.h>
#include <sys/auxv.h>
#include <asm/hwcap.h>

int main() {
	unsigned long hwcap = getauxval(AT_HWCAP);
	unsigned long sve_vl_bits = 0;
	if (hwcap & HWCAP_SVE) {
		asm volatile(
			     "rdvl %0, #1\n"
			     : "=r" (sve_vl_bits)
			    );
		sve_vl_bits *= 8;  //to bit
		printf("SVE vector length: %lu bits\n", sve_vl_bits);
	} else {
		printf("SVE is not supported\n");
	}

	if (hwcap & HWCAP_ASIMD) {
		printf("NEON (ASIMD) is supported and it's 128bit width\n");
	} else {
		printf("NEON (ASIMD) is not supported\n");
	}
	return 0;
}
