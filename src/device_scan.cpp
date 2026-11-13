// SPDX-License-Identifier: GPL-2.0-only
#include "device_scan.h"

#include <libusb.h>
#include <unistd.h>

#include <cstdio>
#include <filesystem>

#include "receiver.h"

namespace studio {

namespace fs = std::filesystem;

std::vector<DeviceInfo> scan_devices() {
  std::vector<DeviceInfo> out;
  libusb_context *ctx = nullptr;
  if (libusb_init(&ctx) != 0)
    return out;
  libusb_device **list = nullptr;
  const ssize_t n = libusb_get_device_list(ctx, &list);
  for (ssize_t i = 0; i < n; i++) {
    libusb_device_descriptor d{};
    if (libusb_get_device_descriptor(list[i], &d) != 0 || d.idVendor != wsdr::usb_vid_for(d.idProduct) ||
        (!wsdr::jaguar2_pid(d.idProduct) && !wsdr::jaguar3_pid(d.idProduct)))
      continue;
    DeviceInfo info;
    info.pid = d.idProduct;
    // Jaguar3 (8812CU, 8812EU): USB 2, 5 MS/s continuous, 40 MS/s gapped, the 8822C code throughout
    const bool cu = wsdr::jaguar3_pid(d.idProduct);
    const bool eu = d.idProduct == wsdr::kPid8812eu;
    info.model = eu ? "RTL8812EU" : cu ? "RTL8812CU" : "RTL8812BU";
    info.chip = eu ? "RTL8822E" : cu ? "RTL8822C" : "RTL8822B";
    info.five_ghz_only = eu; // measured: at 2.4 GHz it streams the ADC floor (wifi-sdr notes/cu-custom-code.md)
    info.bus = libusb_get_bus_number(list[i]);
    uint8_t ports[8];
    const int np = libusb_get_port_numbers(list[i], ports, sizeof ports);
    for (int k = 0; k < np; k++)
      info.port += (k ? "." : "") + std::to_string(ports[k]);
    info.sysfs = std::to_string(info.bus) + "-" + info.port;
    const fs::path dev = fs::path("/sys/bus/usb/devices") / info.sysfs;
    // from libusb, not sysfs, so macOS gets them too (on Linux both report the same)
    switch (libusb_get_device_speed(list[i])) {
    case LIBUSB_SPEED_HIGH: info.speed_mbps = 480; break;
    case LIBUSB_SPEED_SUPER: info.speed_mbps = 5000; break;
    case LIBUSB_SPEED_SUPER_PLUS: info.speed_mbps = 10000; break;
    case LIBUSB_SPEED_FULL: info.speed_mbps = 12; break;
    default: info.speed_mbps = 0; break;
    }
    info.devnum = libusb_get_device_address(list[i]);
    std::error_code ec;
    // /sys/bus/usb/devices/6-1 -> .../0000:67:00.3/usb6/6-1: the PCI device above the root hub.
    for (fs::path p = fs::canonical(dev, ec); !ec && p.has_parent_path() && p != p.root_path();
         p = p.parent_path()) {
      const std::string name = p.filename().string();
      if (name.size() == 12 && name[4] == ':' && name[7] == ':' && name[10] == '.') {
        info.controller = name;
        break;
      }
    }
    const fs::path drv = dev / (info.sysfs + ":1.0") / "driver";
    if (fs::exists(drv, ec))
      info.driver = fs::read_symlink(drv, ec).filename().string();
#ifdef __linux__
    char node[64];
    std::snprintf(node, sizeof node, "/dev/bus/usb/%03d/%03d", info.bus, libusb_get_device_address(list[i]));
    info.can_open = access(node, R_OK | W_OK) == 0;
#else
    info.can_open = true; // no device node to check (macOS): a failed claim at Start reports it instead
#endif
    info.max_msps = !cu && info.speed_mbps >= 5000 ? 40 : 5;
    // gapped spans wider than the link carries: up to 40 MS/s on the 8812CU / 8812EU, 80 MS/s on an 8812BU on
    // either link (wifi-sdr evidence/gapped-80msps.txt)
    info.gapped_msps = cu ? 40 : 80;
    out.push_back(info);
  }
  if (list)
    libusb_free_device_list(list, 1);
  libusb_exit(ctx);
  return out;
}

} // namespace studio
