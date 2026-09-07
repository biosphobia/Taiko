// Godot node exposing PS Move controllers and the PS3 Eye tracker to GDScript.
#pragma once
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <memory>
#include <thread>
#include <mutex>
#include <atomic>
#include <vector>
#include <string>

#include "move_device.h"
#include "hit_detector.h"
#include "eye_tracker.h"
#include "pairing.h"

namespace godot {

class TaikoHW : public Node {
	GDCLASS(TaikoHW, Node)

public:
	static const int MAX_SLOTS = 4;

	TaikoHW();
	~TaikoHW();

	void _ready() override;
	void _process(double delta) override;
	void _exit_tree() override;

	// lifecycle
	void start();
	void stop();
	bool is_started() const { return started.load(); }
	int64_t get_ticks_usec() const;
	String get_version() const;

	// controllers
	int get_slot_count() const { return MAX_SLOTS; }
	Dictionary get_controller_info(int slot);
	Dictionary get_controller_live(int slot);
	Array get_connected_slots();
	void set_led(int slot, const Color &color);
	void set_rumble(int slot, float amount);
	void set_hit_config(const Dictionary &cfg, int slot = -1);
	Dictionary get_hit_config(int slot = 0);
	void reset_detector(int slot);

	// camera
	int camera_device_count();
	bool camera_start(int fps, int width = 320);
	void camera_stop();
	bool camera_running();
	void camera_set_exposure(int v);
	void camera_set_gain(int v);
	void camera_set_auto(bool on);
	void camera_set_flip(bool h, bool v);
	void camera_set_target(int slot, float hue, float tol, float min_sat, float min_val, bool enabled);
	Dictionary camera_get_target(int slot);
	Dictionary camera_get_result(int slot);
	Dictionary camera_get_stats();
	void camera_set_preview(bool on);
	Ref<Image> camera_get_preview();
	Dictionary camera_sample_color(float x, float y, float r);

	// pairing
	bool pairing_supported();
	bool is_elevated();
	bool pair_begin(int slot);
	Dictionary pair_status();
	void pair_cancel();

	// debug / testing without hardware
	void debug_add_virtual(int slot);
	void debug_remove_virtual(int slot);
	void debug_inject(int slot, int64_t t_usec, const Vector3 &accel, const Vector3 &gyro);
	void debug_set_tracking(int slot, bool tracked, const Vector2 &pos);

protected:
	static void _bind_methods();

private:
	struct Event {
		int type = 0; // 0 hit, 1 button, 2 connected, 3 disconnected
		int slot = 0;
		int64_t t = 0;
		float strength = 0;
		int kind = 0;
		bool tracked = false;
		float x = 0, y = 0;
		uint32_t buttons = 0, pressed = 0, released = 0;
	};

	struct Slot {
		std::unique_ptr<taiko::MoveDevice> device;
		std::thread thread;
		std::atomic<bool> stop_flag{ false };
		std::atomic<bool> finished{ false };
		std::atomic<bool> connected{ false };
		std::atomic<bool> is_virtual{ false };
		std::string path;
		std::string serial;
		int model = 0;
		bool bluetooth = false;
		bool calibrated = false;
		// LED / rumble requested by the game (applied by the reader thread)
		std::atomic<uint32_t> led_rgb{ 0 };
		std::atomic<uint8_t> rumble{ 0 };
		std::atomic<bool> led_dirty{ true };
		// detector + live snapshot
		std::mutex mtx;
		taiko::HitDetector detector;
		taiko::ImuSample last_sample;
		uint32_t buttons = 0;
		uint8_t trigger = 0;
		uint8_t battery = 0;
		double period_us = 0;
		int reports = 0;
		// virtual tracking override (tests)
		bool debug_tracked = false;
		float debug_x = 0, debug_y = 0;
	};

	Slot slots[MAX_SLOTS];
	std::thread scan_thread;
	std::atomic<bool> started{ false };
	std::atomic<bool> scan_stop{ false };
	std::mutex event_mutex;
	std::vector<Event> events;
	taiko::HitDetector::Config default_cfg;
	std::mutex cfg_mutex;
	std::unique_ptr<taiko::EyeTracker> tracker;
	taiko::PairingSession pairing;

	void push_event(const Event &e);
	void reader_loop(int slot_index);
	void scan_loop();
	void open_new_devices();
	void reap_finished(bool join_all);
	void close_slot(int i);
	void emit_hit_for(int slot_index, const taiko::HitEvent &h);
	Dictionary config_to_dict(const taiko::HitDetector::Config &c);
	taiko::HitDetector::Config dict_to_config(const Dictionary &d, const taiko::HitDetector::Config &base);
};

} // namespace godot
