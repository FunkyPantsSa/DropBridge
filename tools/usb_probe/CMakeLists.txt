cmake_minimum_required(VERSION 3.15)
project(usb_probe C)

# Same libusb lookup as the devourer build: pkgconf in its default (-I / -l)
# syntax. Do not pass --msvc-syntax: FindPkgConfig only strips -I/-isystem, so
# "/I<path>" leaks through as a bogus absolute include directory.
find_package(PkgConfig REQUIRED)
pkg_check_modules(libusb REQUIRED IMPORTED_TARGET libusb-1.0)

add_executable(usb_probe usb_probe.c)
target_link_libraries(usb_probe PRIVATE PkgConfig::libusb)
