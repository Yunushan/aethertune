#include <cstdio>

extern "C" __declspec(dllimport) const char* Cr_z_zlibVersion();

extern "C" __declspec(dllexport) int fixture() {
  return std::puts(Cr_z_zlibVersion());
}
