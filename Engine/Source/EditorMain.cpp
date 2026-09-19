// This is the actual main for the editor. It should stay at the root of Source and not in some weird
// subdir.

#include "Meta/ReturnInfo.hpp"

int main(int argc, char* argv[])
{
    return static_cast<int>(Meta::ReturnInfo::Code::kSuccess);
}