// PS3 Eye camera capture + colored sphere tracking (for PS Move bulbs).
#pragma once
#include <cstdint>
#include <vector>
#include <thread>
#include <mutex>
#include <atomic>
#include <memory>
#include "move_device.h" // ClockFn

namespace ps3eye { class PS3EYECam; }

namespace taiko {

static const int MAX_TRACK_TARGETS = 4;

struct TrackTarget {
	bool enabled = false;
	float hue = 0.0f; // degrees 0..360
	float hue_tol = 25.0f; // degrees
	float min_sat = 0.35f; // 0..1
	float min_val = 0.25f; // 0..1
};

struct TrackResult {
	bool tracked = false;
	float x = 0, y = 0; // pixel coordinates (frame space)
	float radius = 0;
	int pixels = 0;
	int64_t t_usec = 0; // estimated exposure time of the frame
	uint32_t frame_id = 0;
};

struct CameraStats {
	bool running = false;
	int width = 0, height = 0, fps_setting = 0;
	float fps_measured = 0;
	uint32_t frames = 0;
	int bright_pixels = 0; // near-saturated pixels
	int stray_bright = 0; // bright pixels outside tracked blobs
	int64_t last_frame_t = 0;
	float process_ms = 0; // blob processing time of the last frame
};

class EyeTracker {
public:
	explicit EyeTracker(ClockFn clock);
	~EyeTracker();

	static int device_count();
	bool start(int width, int height, int fps);
	void stop();
	bool running() const { return is_running.load(); }

	void set_exposure(int v); // 0..255
	void set_gain(int v); // 0..63
	void set_auto_gain(bool on);
	void set_auto_white_balance(bool on);
	void set_flip(bool h, bool v);
	int exposure() const { return cur_exposure; }
	int gain() const { return cur_gain; }

	void set_target(int idx, const TrackTarget &t);
	TrackTarget get_target(int idx);
	TrackResult get_result(int idx);
	CameraStats get_stats();

	void set_preview_enabled(bool on) { preview_enabled.store(on); }
	// Copies the latest RGB frame; returns false if none is available.
	bool copy_preview(std::vector<uint8_t> &rgb, int &w, int &h);
	// Dominant color of bright, saturated pixels inside a circle of the latest frame.
	bool sample_color(float cx, float cy, float r, float &hue, float &sat, float &val, int &count);

private:
	ClockFn now;
	std::shared_ptr<ps3eye::PS3EYECam> cam;
	std::thread worker;
	std::atomic<bool> is_running{ false };
	std::atomic<bool> stop_requested{ false };
	std::atomic<bool> preview_enabled{ false };
	int width = 320, height = 240, fps = 125;
	int cur_exposure = 60, cur_gain = 10;

	std::mutex target_mutex;
	TrackTarget targets[MAX_TRACK_TARGETS];
	std::mutex result_mutex;
	TrackResult results[MAX_TRACK_TARGETS];
	CameraStats stats;
	std::mutex frame_mutex;
	std::vector<uint8_t> preview; // RGB copy of the latest frame
	std::vector<uint8_t> latest; // RGB working copy for sampling

	std::vector<uint8_t> frame_buf;
	std::vector<uint8_t> cls; // per-pixel class (0 = none, 1..N = target)
	std::vector<int32_t> labels;
	std::vector<int32_t> parent;

	void loop();
	void process_frame(const uint8_t *rgb, int64_t t);
};

// RGB (0..255) -> HSV (hue degrees, sat 0..1, val 0..1)
void rgb_to_hsv(uint8_t r, uint8_t g, uint8_t b, float &h, float &s, float &v);

} // namespace taiko
