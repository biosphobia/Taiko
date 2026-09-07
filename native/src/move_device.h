// PS Move (CECH-ZCM1 and CECH-ZCM2 / "PS4 Move") HID protocol layer.
// Report layouts follow the psmoveapi project (BSD-2) and the moveonpc wiki.
#pragma once
#include <cstdint>
#include <string>
#include <vector>
#include "hit_detector.h"

struct hid_device_;
struct hid_device_info;

namespace taiko {

typedef int64_t (*ClockFn)();

enum MoveModel { MODEL_ZCM1 = 0, MODEL_ZCM2 = 1 };

// Button bits (same layout as psmoveapi's enum PSMove_Button)
enum MoveButton : uint32_t {
	BTN_TRIANGLE = 1u << 4,
	BTN_CIRCLE = 1u << 5,
	BTN_CROSS = 1u << 6,
	BTN_SQUARE = 1u << 7,
	BTN_SELECT = 1u << 8,
	BTN_START = 1u << 11,
	BTN_PS = 1u << 16,
	BTN_MOVE = 1u << 19,
	BTN_T = 1u << 20,
};

// Converts host arrival times of reports into a smooth, monotonic sample timeline.
// Bluetooth delivery jitters and sometimes batches reports; the controller itself emits
// them at a fixed rate, so we lock a software PLL to the sequence numbers.
class ReportClock {
public:
	void reset(double initial_period_us = 11500.0);
	int64_t stamp(int64_t arrival_usec, int seq4bit);
	double period_us() const { return period; }

private:
	bool initialized = false;
	double period = 11500.0;
	int64_t smooth = 0;
	int64_t prev_arrival = 0;
	int last_seq = -1;
	int count = 0;
};

struct MoveCalibration {
	bool valid = false;
	float ax = 1, ay = 1, az = 1; // accel factors
	float bx = 0, by = 0, bz = 0; // accel offsets
	float gx = 1, gy = 1, gz = 1; // gyro factors
	int dx = 0, dy = 0, dz = 0; // gyro raw bias
};

class MoveDevice {
public:
	explicit MoveDevice(ClockFn clock);
	~MoveDevice();

	// Opens the device. On Windows, info must be the "col01" collection; the sibling
	// "col02" collection (used for Bluetooth-address feature reports) is looked up in `all`.
	bool open(const hid_device_info *info, const hid_device_info *all);
	void close();
	bool is_open() const { return handle != nullptr; }

	// Reads one input report (blocking up to timeout_ms). Returns the number of IMU samples
	// written to out (0, 1 or 2), or -1 when the device is gone.
	int poll(int timeout_ms, ImuSample out[2]);

	bool write_leds(uint8_t r, uint8_t g, uint8_t b, uint8_t rumble);
	bool read_bt_addrs(uint8_t controller[6], uint8_t host[6]);
	bool set_host_bt_addr(const uint8_t host[6]);
	bool read_calibration();

	static std::string btaddr_to_string(const uint8_t addr[6]);
	static bool btaddr_from_string(const std::string &s, uint8_t out[6]);

	const std::string &serial() const { return serial_str; }
	MoveModel model() const { return model_type; }
	bool is_bluetooth() const { return bluetooth; }
	const std::string &path() const { return device_path; }
	uint32_t buttons() const { return last_buttons; }
	uint8_t trigger() const { return last_trigger; }
	uint8_t battery() const { return last_battery; }
	const MoveCalibration &calibration() const { return cal; }
	double sample_period_us() const { return clock.period_us(); }
	const ImuSample &last_sample() const { return last_imu; }
	int report_count() const { return reports; }

private:
	ClockFn now;
	hid_device_ *handle = nullptr;
	hid_device_ *handle_addr = nullptr; // Windows only
	std::string device_path;
	std::string serial_str;
	MoveModel model_type = MODEL_ZCM1;
	bool bluetooth = false;
	MoveCalibration cal;
	ReportClock clock;
	uint32_t last_buttons = 0;
	uint8_t last_trigger = 0;
	uint8_t last_battery = 0;
	ImuSample last_imu;
	int reports = 0;
	// fallback accelerometer scale estimation when no calibration blob could be read
	float fallback_accel_scale = 1.0f / 4096.0f;
	float fallback_gyro_scale = 1.0f / 900.0f;
	int rest_counter = 0;

	hid_device_ *feature_handle() const { return handle_addr ? handle_addr : handle; }
	void decode_common(const unsigned char *buf);
	void raw_to_sample(const unsigned char *buf, int frame, int64_t t, ImuSample &out);
	void update_fallback_scale(int rax, int ray, int raz, int rgx, int rgy, int rgz);
};

// Enumerates connected PS Move controllers (main data collection only). Returns paths.
struct MoveDeviceEntry {
	std::string path;
	unsigned short pid;
	bool bluetooth;
	std::string serial_hint;
};
std::vector<MoveDeviceEntry> enumerate_move_devices();

} // namespace taiko
