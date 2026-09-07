// Bluetooth pairing helper for PS Move controllers connected over USB.
// Writes the host adapter address into the controller and (on Windows) registers the
// controller with the Bluetooth stack the way psmoveapi's "psmove pair" does.
#pragma once
#include <string>
#include <thread>
#include <mutex>
#include <atomic>
#include <cstdint>

namespace taiko {

class MoveDevice;

struct PairingStatus {
	bool active = false;
	bool done = false;
	bool success = false;
	int step = 0; // 0 idle, 1 reading addresses, 2 writing host address, 3 waiting for Bluetooth connection, 4 registered
	std::string message;
	std::string controller_addr;
	std::string host_addr;
};

class PairingSession {
public:
	~PairingSession();
	static bool supported();
	static bool is_elevated();
	static bool get_host_bt_address(uint8_t out[6], std::string &err);

	// Step 1 is done synchronously on the calling thread with an open device (writes the host
	// address into the controller). Step 2 (waiting for the controller to connect over Bluetooth)
	// runs on a worker thread; the caller must unplug the USB cable and press the PS button.
	bool begin(MoveDevice *usb_device, int model);
	void cancel();
	PairingStatus status();

private:
	std::thread worker;
	std::atomic<bool> cancel_flag{ false };
	std::mutex mtx;
	PairingStatus st;
	uint8_t controller_addr[6] = { 0 };
	uint8_t host_addr[6] = { 0 };
	int model_type = 0;

	void set(int step, const std::string &msg, bool done = false, bool success = false);
	void run();
};

} // namespace taiko
