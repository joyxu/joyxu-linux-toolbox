//----------------------------------------------------------------------------
//
// Arm64 CPU system registers tools
// Display HWCAP as returned by getauxval().
//
//----------------------------------------------------------------------------

#include "strutils.h"

#include <iostream>
#include <vector>
#include <cstddef>
#include <cstdlib>
#include <sys/auxv.h>
#include <asm/hwcap.h>

// Hardware capabilities.
struct CapName {
    std::string name;
    unsigned long type;
    unsigned long flag;
};
const std::vector<CapName> AllCapNames {
    #include "arm64_hwcaps.h"
};

// Program entry point
int main(int argc, char* argv[])
{
    size_t name_width = 0;
    for (const auto& cap : AllCapNames) {
        name_width = std::max(name_width, cap.name.length());
    }
    for (const auto& cap : AllCapNames) {
        std::cout << Pad(cap.name + " ", name_width + 1) << " " << YesNo(::getauxval(cap.type) & cap.flag) << std::endl;
    }
    return EXIT_SUCCESS;
}
