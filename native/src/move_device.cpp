#include "move_device.h"
#include "hidapi.h"
#include <cstring>
#include <cstdio>
#include <algorithm>
#include <cmath>
#include <cwchar>

namespace taiko {

static const unsigned short MOVE_VID = 0x054c;
static const unsigned short MOVE_PID_ZCM1 = 0x03d5;
static const unsigned short MOVE_PID_ZCM2 = 0x0c5e;

enum Req {
	REQ_GET_INPUT = 0x01,
	REQ_SET_LEDS = 0x06,
	REQ_GET_BTADDR = 0x04,
	REQ_SET_BTADDR = 0x05,
	REQ_GET_CALIBRATION = 0x10,
};

// Offsets in the input report (identical prefix for both models)
enum Off {
	O_TYPE = 0, O_BTN1 = 1, O_BTN2 = 2, O_BTN3 = 3, O_BTN4 = 4, O_TRIGGER = 5, O_TRIGGER2 = 6,
	O_TIMEHIGH = 11, O_BATTERY = 12, O_AX = 13, O_AX2 = 19, O_GX = 25, O_GX2 = 31,
};
static const int ZCM1_REPORT_SIZE = 49; // 39 common + 4 mag + timelow + 5 ext
static const int ZCM2_REPORT_SIZE = 44; // 39 common + 5
static const int CAL_BLOCK = 49;

// ---------------------------------------------------------------------------------------------
void ReportClock::reset(double initial_period_us) {
	initialized = false;
	period = initial_period_us;
	last_seq = -1;
	count = 0;
}

int64_t ReportClock::stamp(int64_t arrival, int seq) {
	if (!initialized) {
		initialized = true;
		smooth = arrival;
		prev_arrival = arrival;
		last_seq = seq;
		count = 1;
		return arrival;
	}
	int d = (seq - last_seq) & 0x0F;
	if (d == 0) d = 16;
	last_seq = seq;
	count++;

	int64_t predicted = smooth + (int64_t)(period * d + 0.5);
	int64_t err = arrival - predicted;
	// The controller keeps emitting on its own schedule; a late delivery (Bluetooth retransmit or
	// batching) does not move that schedule, so late arrivals are trusted to the prediction as long
	// as the 4-bit sequence counter is still unambiguous (~14 reports). Early arrivals mean our
	// estimate lags and are corrected immediately.
	const int64_t late_limit = (int64_t)std::max(40000.0, 14.0 * period);
	if (err < -40000 || err > late_limit) {
		smooth = arrival;
	} else {
		double gain = (count < 200) ? 0.08 : 0.02;
		if (err > 20000) gain = 0.005; // stalled delivery: barely move the schedule
		smooth = predicted + (int64_t)(err * gain);
		// Adapt the period slowly from the mean arrival spacing (ignoring stalls).
		double measured = (double)(arrival - prev_arrival) / d;
		if (measured > 1000.0 && measured < 40000.0 && err < 20000 && err > -20000) {
			double pg = (count < 200) ? 0.05 : 0.002;
			period += (measured - period) * pg;
		}
	}
	prev_arrival = arrival;
	// A report cannot be generated after it arrived; if it arrived early our estimate lags.
	int64_t ts = std::min(arrival, smooth);
	if (ts > arrival) ts = arrival;
	return ts;
}

// ---------------------------------------------------------------------------------------------
static inline int decode16_offset(const unsigned char *d, int off) {
	return (int)(d[off] | (d[off + 1] << 8)) - 0x8000;
}
static inline int decode16_signed(const unsigned char *d, int off) {
	return (int)(int16_t)(d[off] | (d[off + 1] << 8));
}

static std::string lower(std::string s) {
	std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return (char)std::tolower(c); });
	return s;
}

MoveDevice::MoveDevice(ClockFn clock_fn) : now(clock_fn) {}
MoveDevice::~MoveDevice() { close(); }

bool MoveDevice::open(const hid_device_info *info, const hid_device_info *all) {
	close();
	if (!info || !info->path) return false;
	device_path = info->path;
	model_type = (info->product_id == MOVE_PID_ZCM2) ? MODEL_ZCM2 : MODEL_ZCM1;
	bluetooth = (info->bus_type == HID_API_BUS_BLUETOOTH);
#ifdef TAIKO_WINDOWS
	// hidapi reports HID_API_BUS_UNKNOWN for some Bluetooth stacks; fall back to the serial heuristic.
	if (info->bus_type == HID_API_BUS_UNKNOWN) {
		bluetooth = info->serial_number && std::wcslen(info->serial_number) > 1;
	}
	// Find the col02 sibling collection for Bluetooth-address feature reports.
	std::string lp = lower(device_path);
	size_t cpos = lp.find("&col01#");
	if (cpos != std::string::npos) {
		std::string prefix = lp.substr(0, cpos);
		for (const hid_device_info *d = all; d; d = d->next) {
			if (!d->path || d->vendor_id != info->vendor_id || d->product_id != info->product_id) continue;
			std::string dp = lower(d->path);
			if (dp.compare(0, prefix.size(), prefix) == 0 && dp.find("&col02#") != std::string::npos) {
				handle_addr = hid_open_path(d->path);
				break;
			}
		}
	}
#endif
	handle = hid_open_path(info->path);
	if (!handle) {
		if (handle_addr) { hid_close(handle_addr); handle_addr = nullptr; }
		return false;
	}
	hid_set_nonblocking(handle, 0);

	// Serial number: Bluetooth address of the controller.
	serial_str.clear();
	if (info->serial_number && std::wcslen(info->serial_number) > 1) {
		char buf[64] = {0};
		std::wcstombs(buf, info->serial_number, sizeof(buf) - 1);
		serial_str = lower(buf);
		for (auto &c : serial_str) if (c == '-') c = ':';
	}
	if (serial_str.size() != 17) {
		uint8_t ctrl[6], host[6];
		if (read_bt_addrs(ctrl, host)) {
			serial_str = btaddr_to_string(ctrl);
		} else {
			serial_str = "unknown-" + device_path.substr(device_path.size() > 12 ? device_path.size() - 12 : 0);
		}
	}
	clock.reset(model_type == MODEL_ZCM1 ? 11500.0 : 8000.0);
	reports = 0;
	rest_counter = 0;
	read_calibration();
	return true;
}

void MoveDevice::close() {
	if (handle) { hid_close(handle); handle = nullptr; }
	if (handle_addr) { hid_close(handle_addr); handle_addr = nullptr; }
}

void MoveDevice::decode_common(const unsigned char *b) {
	last_buttons = (uint32_t)b[O_BTN2] | ((uint32_t)b[O_BTN1] << 8) | (((uint32_t)b[O_BTN3] & 0x01) << 16) | (((uint32_t)b[O_BTN4] & 0xF0) << 13);
	last_trigger = (model_type == MODEL_ZCM1) ? (uint8_t)(((int)b[O_TRIGGER] + (int)b[O_TRIGGER2]) / 2) : b[O_TRIGGER];
	last_battery = b[O_BATTERY];
}

void MoveDevice::update_fallback_scale(int rax, int ray, int raz, int rgx, int rgy, int rgz) {
	// When the controller is (nearly) still, the accelerometer magnitude must be 1 g.
	double gmag = std::sqrt((double)rgx * rgx + (double)rgy * rgy + (double)rgz * rgz);
	double amag = std::sqrt((double)rax * rax + (double)ray * ray + (double)raz * raz);
	if (gmag * fallback_gyro_scale < 0.15 && amag > 500.0) {
		rest_counter++;
		if (rest_counter > 20) {
			float target = (float)(1.0 / amag);
			fallback_accel_scale += (target - fallback_accel_scale) * 0.05f;
		}
	} else {
		rest_counter = 0;
	}
}

void MoveDevice::raw_to_sample(const unsigned char *b, int frame, int64_t t, ImuSample &out) {
	int rax, ray, raz, rgx, rgy, rgz;
	if (model_type == MODEL_ZCM1) {
		int ao = (frame == 0) ? O_AX : O_AX2;
		int go = (frame == 0) ? O_GX : O_GX2;
		rax = decode16_offset(b, ao); ray = decode16_offset(b, ao + 2); raz = decode16_offset(b, ao + 4);
		rgx = decode16_offset(b, go); rgy = decode16_offset(b, go + 2); rgz = decode16_offset(b, go + 4);
	} else {
		rax = decode16_signed(b, O_AX); ray = decode16_signed(b, O_AX + 2); raz = decode16_signed(b, O_AX + 4);
		rgx = decode16_signed(b, O_GX); rgy = decode16_signed(b, O_GX + 2); rgz = decode16_signed(b, O_GX + 4);
	}
	out.t_usec = t;
	if (cal.valid) {
		out.accel = Vec3((float)rax * cal.ax + cal.bx, (float)ray * cal.ay + cal.by, (float)raz * cal.az + cal.bz);
		out.gyro = Vec3((float)(rgx - cal.dx) * cal.gx, (float)(rgy - cal.dy) * cal.gy, (float)(rgz - cal.dz) * cal.gz);
	} else {
		update_fallback_scale(rax, ray, raz, rgx, rgy, rgz);
		out.accel = Vec3((float)rax, (float)ray, (float)raz) * fallback_accel_scale;
		out.gyro = Vec3((float)rgx, (float)rgy, (float)rgz) * fallback_gyro_scale;
	}
}

int MoveDevice::poll(int timeout_ms, ImuSample out[2]) {
	if (!handle) return -1;
	unsigned char buf[64];
	memset(buf, 0, sizeof(buf));
	const int expected = (model_type == MODEL_ZCM1) ? ZCM1_REPORT_SIZE : ZCM2_REPORT_SIZE;
	int res = hid_read_timeout(handle, buf, sizeof(buf), timeout_ms);
	int64_t arrival = now();
	if (res < 0) return -1;
	if (res == 0) return 0;
	if (buf[0] != REQ_GET_INPUT) return 0;
	if (res < 37) return 0; // need at least the first IMU frame
	(void)expected;
	reports++;
	decode_common(buf);
	int seq = buf[O_BTN4] & 0x0F;
	int64_t t = clock.stamp(arrival, seq);
	int n = 0;
	if (model_type == MODEL_ZCM1) {
		int64_t half = (int64_t)(clock.period_us() * 0.5);
		raw_to_sample(buf, 0, t - half, out[0]);
		raw_to_sample(buf, 1, t, out[1]);
		n = 2;
	} else {
		raw_to_sample(buf, 0, t, out[0]);
		n = 1;
	}
	last_imu = out[n - 1];
	return n;
}

bool MoveDevice::write_leds(uint8_t r, uint8_t g, uint8_t b, uint8_t rumble) {
	if (!handle) return false;
	unsigned char rep[9] = { REQ_SET_LEDS, 0x00, r, g, b, 0x00, rumble, 0x00, 0x00 };
	return hid_write(handle, rep, sizeof(rep)) >= 0;
}

bool MoveDevice::read_bt_addrs(uint8_t controller[6], uint8_t host[6]) {
	if (!handle) return false;
	unsigned char btg[20];
	memset(btg, 0, sizeof(btg));
	btg[0] = REQ_GET_BTADDR;
	int res = hid_get_feature_report(feature_handle(), btg, sizeof(btg));
	if (res < 16) return false;
	if (controller) memcpy(controller, btg + 1, 6);
	if (host) memcpy(host, btg + 10, 6);
	return true;
}

bool MoveDevice::set_host_bt_addr(const uint8_t host[6]) {
	if (!handle) return false;
	unsigned char bts[23];
	memset(bts, 0, sizeof(bts));
	bts[0] = REQ_SET_BTADDR;
	memcpy(bts + 1, host, 6);
	int res = hid_send_feature_report(feature_handle(), bts, sizeof(bts));
	return res == (int)sizeof(bts);
}

static std::string g_cache_dir;

void MoveDevice::set_cache_dir(const std::string &dir) {
	g_cache_dir = dir;
}

std::string MoveDevice::cache_path() const {
	if (g_cache_dir.empty() || serial_str.empty()) return "";
	std::string name;
	for (char c : serial_str) name += (c == ':') ? '_' : c;
	return g_cache_dir + "/" + name + (model_type == MODEL_ZCM2 ? ".zcm2.cal" : ".zcm1.cal");
}

bool MoveDevice::load_cached_blob(std::vector<uint8_t> &blob) {
	std::string p = cache_path();
	if (p.empty()) return false;
	FILE *f = fopen(p.c_str(), "rb");
	if (!f) return false;
	blob.assign(CAL_BLOCK * 3, 0);
	size_t n = fread(blob.data(), 1, blob.size(), f);
	fclose(f);
	const size_t expected = (model_type == MODEL_ZCM1) ? (size_t)(CAL_BLOCK * 3 - 4) : (size_t)(CAL_BLOCK * 2 - 2);
	return n == expected;
}

void MoveDevice::save_cached_blob(const std::vector<uint8_t> &blob) {
	std::string p = cache_path();
	if (p.empty()) return;
	FILE *f = fopen(p.c_str(), "wb");
	if (!f) return;
	const size_t expected = (model_type == MODEL_ZCM1) ? (size_t)(CAL_BLOCK * 3 - 4) : (size_t)(CAL_BLOCK * 2 - 2);
	fwrite(blob.data(), 1, std::min(expected, blob.size()), f);
	fclose(f);
}

bool MoveDevice::read_calibration() {
	cal = MoveCalibration();
	if (!handle) return false;
	std::vector<uint8_t> blob;
	// The calibration report is reliable over USB; over Bluetooth it is often unavailable, so the
	// blob captured over USB is cached per controller and reused.
	if (!bluetooth) {
		if (acquire_calibration_blob(blob) && parse_calibration_blob(blob.data())) {
			save_cached_blob(blob);
			return true;
		}
		return false;
	}
	if (load_cached_blob(blob) && parse_calibration_blob(blob.data())) return true;
	if (acquire_calibration_blob(blob) && parse_calibration_blob(blob.data())) {
		save_cached_blob(blob);
		return true;
	}
	cal = MoveCalibration();
	return false;
}

bool MoveDevice::acquire_calibration_blob(std::vector<uint8_t> &out) {
	out.assign(CAL_BLOCK * 3, 0);
	uint8_t *blob = out.data();
	const int blocks = (model_type == MODEL_ZCM1) ? 3 : 2;
	bool got[3] = { false, false, false };
	for (int attempt = 0; attempt < blocks + 2; attempt++) {
		unsigned char part[CAL_BLOCK];
		memset(part, 0, sizeof(part));
		part[0] = REQ_GET_CALIBRATION;
		int res = hid_get_feature_report(handle, part, sizeof(part));
		if (res != CAL_BLOCK) return false;
		int idx, dest, src;
		if (part[1] == 0x00) { idx = 0; dest = 0; src = 0; }
		else if (model_type == MODEL_ZCM1 && part[1] == 0x01) { idx = 1; dest = CAL_BLOCK; src = 2; }
		else if (model_type == MODEL_ZCM1 && part[1] == 0x82) { idx = 2; dest = 2 * CAL_BLOCK - 2; src = 2; }
		else if (model_type == MODEL_ZCM2 && part[1] == 0x81) { idx = 1; dest = CAL_BLOCK; src = 2; }
		else return false;
		memcpy(blob + dest, part + src, CAL_BLOCK - src);
		got[idx] = true;
		bool all = true;
		for (int i = 0; i < blocks; i++) all = all && got[i];
		if (all) break;
	}
	for (int i = 0; i < blocks; i++) if (!got[i]) return false;
	return true;
}

bool MoveDevice::parse_calibration_blob(const uint8_t *blob) {
	cal = MoveCalibration();
	int axlow, axhigh, aylow, ayhigh, azlow, azhigh;
	if (model_type == MODEL_ZCM1) {
		auto u = [&](int off) { return decode16_offset(blob, off); };
		axlow = u(0x04 + 6 * 1); aylow = u(0x04 + 6 * 5 + 2); azlow = u(0x04 + 6 * 2 + 4);
		axhigh = u(0x04 + 6 * 3); ayhigh = u(0x04 + 6 * 4 + 2); azhigh = u(0x04 + 6 * 0 + 4);
		int bx = u(0x2a), by = u(0x2a + 2), bz = u(0x2a + 4);
		int gx80 = u(0x46 + 8 * 0) - bx, gy80 = u(0x46 + 8 * 1 + 2) - by, gz80 = u(0x46 + 8 * 2 + 4) - bz;
		if (axhigh == axlow || ayhigh == aylow || azhigh == azlow || gx80 == 0 || gy80 == 0 || gz80 == 0) return false;
		const float rpm_to_rad = (2.0f * (float)M_PI) / 60.0f;
		const float factor = 80.0f * rpm_to_rad;
		cal.gx = factor / (float)gx80; cal.gy = factor / (float)gy80; cal.gz = factor / (float)gz80;
		cal.dx = cal.dy = cal.dz = 0;
	} else {
		auto sg = [&](int off) { return decode16_signed(blob, off); };
		axlow = sg(0x02 + 6 * 1); aylow = sg(0x02 + 6 * 3 + 2); azlow = sg(0x02 + 6 * 5 + 4);
		axhigh = sg(0x02 + 6 * 0); ayhigh = sg(0x02 + 6 * 2 + 2); azhigh = sg(0x02 + 6 * 4 + 4);
		int gx1 = sg(0x30 + 6 * 3), gy1 = sg(0x30 + 6 * 4 + 2), gz1 = sg(0x30 + 6 * 5 + 4);
		int gx2 = sg(0x30 + 6 * 0), gy2 = sg(0x30 + 6 * 1 + 2), gz2 = sg(0x30 + 6 * 2 + 4);
		cal.dx = sg(0x26); cal.dy = sg(0x26 + 2); cal.dz = sg(0x26 + 4);
		if (axhigh == axlow || ayhigh == aylow || azhigh == azlow || gx2 == gx1 || gy2 == gy1 || gz2 == gz1) return false;
		const float rpm_to_rad = (2.0f * (float)M_PI) / 60.0f;
		const float factor = 2.0f * 90.0f * rpm_to_rad;
		cal.gx = factor / (float)(gx2 - gx1); cal.gy = factor / (float)(gy2 - gy1); cal.gz = factor / (float)(gz2 - gz1);
	}
	cal.ax = 2.0f / (float)(axhigh - axlow); cal.ay = 2.0f / (float)(ayhigh - aylow); cal.az = 2.0f / (float)(azhigh - azlow);
	cal.bx = -(cal.ax * (float)axlow) - 1.0f; cal.by = -(cal.ay * (float)aylow) - 1.0f; cal.bz = -(cal.az * (float)azlow) - 1.0f;
	// Sanity: reject absurd factors (garbage blob)
	if (!(std::fabs(cal.ax) < 0.01f && std::fabs(cal.ay) < 0.01f && std::fabs(cal.az) < 0.01f)) return false;
	if (!(std::fabs(cal.gx) < 0.1f && std::fabs(cal.gy) < 0.1f && std::fabs(cal.gz) < 0.1f)) return false;
	cal.valid = true;
	return true;
}

std::string MoveDevice::btaddr_to_string(const uint8_t a[6]) {
	char buf[32];
	snprintf(buf, sizeof(buf), "%02x:%02x:%02x:%02x:%02x:%02x", a[5], a[4], a[3], a[2], a[1], a[0]);
	return buf;
}

bool MoveDevice::btaddr_from_string(const std::string &s, uint8_t out[6]) {
	if (s.size() != 17) return false;
	for (int i = 0; i < 6; i++) {
		char *end = nullptr;
		long v = strtol(s.c_str() + i * 3, &end, 16);
		if (v < 0 || v > 255 || (end - (s.c_str() + i * 3)) != 2) return false;
		if (i < 5 && s[i * 3 + 2] != ':' && s[i * 3 + 2] != '-') return false;
		out[5 - i] = (uint8_t)v;
	}
	return true;
}

std::vector<MoveDeviceEntry> enumerate_move_devices() {
	std::vector<MoveDeviceEntry> result;
	const unsigned short pids[2] = { MOVE_PID_ZCM1, MOVE_PID_ZCM2 };
	for (int p = 0; p < 2; p++) {
		hid_device_info *devs = hid_enumerate(MOVE_VID, pids[p]);
		for (hid_device_info *d = devs; d; d = d->next) {
			if (!d->path) continue;
#ifdef TAIKO_WINDOWS
			std::string lp = lower(d->path);
			if (lp.find("&col01#") == std::string::npos) continue;
#endif
			MoveDeviceEntry e;
			e.path = d->path;
			e.pid = d->product_id;
			e.bluetooth = (d->bus_type == HID_API_BUS_BLUETOOTH);
			if (d->serial_number) {
				char buf[64] = {0};
				std::wcstombs(buf, d->serial_number, sizeof(buf) - 1);
				e.serial_hint = buf;
			}
			result.push_back(e);
		}
		hid_free_enumeration(devs);
	}
	return result;
}

} // namespace taiko
