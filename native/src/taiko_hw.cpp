#include "taiko_hw.h"
#include "hidapi.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include <chrono>
#include <cstring>

using namespace godot;

static int64_t taiko_clock() {
	return Time::get_singleton()->get_ticks_usec();
}

TaikoHW::TaikoHW() {}

TaikoHW::~TaikoHW() {
	stop();
}

void TaikoHW::_bind_methods() {
	ClassDB::bind_method(D_METHOD("start"), &TaikoHW::start);
	ClassDB::bind_method(D_METHOD("stop"), &TaikoHW::stop);
	ClassDB::bind_method(D_METHOD("is_started"), &TaikoHW::is_started);
	ClassDB::bind_method(D_METHOD("get_ticks_usec"), &TaikoHW::get_ticks_usec);
	ClassDB::bind_method(D_METHOD("get_version"), &TaikoHW::get_version);

	ClassDB::bind_method(D_METHOD("get_slot_count"), &TaikoHW::get_slot_count);
	ClassDB::bind_method(D_METHOD("get_controller_info", "slot"), &TaikoHW::get_controller_info);
	ClassDB::bind_method(D_METHOD("get_controller_live", "slot"), &TaikoHW::get_controller_live);
	ClassDB::bind_method(D_METHOD("get_connected_slots"), &TaikoHW::get_connected_slots);
	ClassDB::bind_method(D_METHOD("set_led", "slot", "color"), &TaikoHW::set_led);
	ClassDB::bind_method(D_METHOD("set_rumble", "slot", "amount"), &TaikoHW::set_rumble);
	ClassDB::bind_method(D_METHOD("set_hit_config", "config", "slot"), &TaikoHW::set_hit_config, DEFVAL(-1));
	ClassDB::bind_method(D_METHOD("get_hit_config", "slot"), &TaikoHW::get_hit_config, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("reset_detector", "slot"), &TaikoHW::reset_detector);

	ClassDB::bind_method(D_METHOD("camera_device_count"), &TaikoHW::camera_device_count);
	ClassDB::bind_method(D_METHOD("camera_start", "fps", "width"), &TaikoHW::camera_start, DEFVAL(320));
	ClassDB::bind_method(D_METHOD("camera_stop"), &TaikoHW::camera_stop);
	ClassDB::bind_method(D_METHOD("camera_running"), &TaikoHW::camera_running);
	ClassDB::bind_method(D_METHOD("camera_set_exposure", "value"), &TaikoHW::camera_set_exposure);
	ClassDB::bind_method(D_METHOD("camera_set_gain", "value"), &TaikoHW::camera_set_gain);
	ClassDB::bind_method(D_METHOD("camera_set_auto", "on"), &TaikoHW::camera_set_auto);
	ClassDB::bind_method(D_METHOD("camera_set_flip", "horizontal", "vertical"), &TaikoHW::camera_set_flip);
	ClassDB::bind_method(D_METHOD("camera_set_target", "slot", "hue", "tolerance", "min_sat", "min_val", "enabled"), &TaikoHW::camera_set_target);
	ClassDB::bind_method(D_METHOD("camera_get_target", "slot"), &TaikoHW::camera_get_target);
	ClassDB::bind_method(D_METHOD("camera_get_result", "slot"), &TaikoHW::camera_get_result);
	ClassDB::bind_method(D_METHOD("camera_get_stats"), &TaikoHW::camera_get_stats);
	ClassDB::bind_method(D_METHOD("camera_set_preview", "on"), &TaikoHW::camera_set_preview);
	ClassDB::bind_method(D_METHOD("camera_get_preview"), &TaikoHW::camera_get_preview);
	ClassDB::bind_method(D_METHOD("camera_sample_color", "x", "y", "radius"), &TaikoHW::camera_sample_color);

	ClassDB::bind_method(D_METHOD("pairing_supported"), &TaikoHW::pairing_supported);
	ClassDB::bind_method(D_METHOD("is_elevated"), &TaikoHW::is_elevated);
	ClassDB::bind_method(D_METHOD("pair_begin", "slot"), &TaikoHW::pair_begin);
	ClassDB::bind_method(D_METHOD("pair_status"), &TaikoHW::pair_status);
	ClassDB::bind_method(D_METHOD("pair_cancel"), &TaikoHW::pair_cancel);

	ClassDB::bind_method(D_METHOD("debug_add_virtual", "slot"), &TaikoHW::debug_add_virtual);
	ClassDB::bind_method(D_METHOD("debug_remove_virtual", "slot"), &TaikoHW::debug_remove_virtual);
	ClassDB::bind_method(D_METHOD("debug_inject", "slot", "t_usec", "accel", "gyro"), &TaikoHW::debug_inject);
	ClassDB::bind_method(D_METHOD("debug_set_tracking", "slot", "tracked", "pos"), &TaikoHW::debug_set_tracking);

	ADD_SIGNAL(MethodInfo("hit", PropertyInfo(Variant::INT, "slot"), PropertyInfo(Variant::INT, "t_usec"), PropertyInfo(Variant::FLOAT, "strength"), PropertyInfo(Variant::INT, "kind"), PropertyInfo(Variant::BOOL, "tracked"), PropertyInfo(Variant::VECTOR2, "pos")));
	ADD_SIGNAL(MethodInfo("button", PropertyInfo(Variant::INT, "slot"), PropertyInfo(Variant::INT, "buttons"), PropertyInfo(Variant::INT, "pressed"), PropertyInfo(Variant::INT, "released")));
	ADD_SIGNAL(MethodInfo("controller_connected", PropertyInfo(Variant::INT, "slot")));
	ADD_SIGNAL(MethodInfo("controller_disconnected", PropertyInfo(Variant::INT, "slot")));

	BIND_CONSTANT(MAX_SLOTS);
}

// ------------------------------------------------------------------------------------------
void TaikoHW::_ready() {
	set_process(true);
}

void TaikoHW::_exit_tree() {
	stop();
}

int64_t TaikoHW::get_ticks_usec() const {
	return taiko_clock();
}

String TaikoHW::get_version() const {
	return "taiko_hw 1.0";
}

void TaikoHW::start() {
	if (started.load()) return;
	if (Engine::get_singleton()->is_editor_hint()) return;
	hid_init();
	tracker.reset(new taiko::EyeTracker(taiko_clock));
	scan_stop.store(false);
	started.store(true);
	scan_thread = std::thread(&TaikoHW::scan_loop, this);
}

void TaikoHW::stop() {
	if (!started.load()) return;
	started.store(false);
	scan_stop.store(true);
	if (scan_thread.joinable()) scan_thread.join();
	pairing.cancel();
	for (int i = 0; i < MAX_SLOTS; i++) close_slot(i);
	if (tracker) tracker->stop();
	tracker.reset();
	hid_exit();
}

void TaikoHW::push_event(const Event &e) {
	std::lock_guard<std::mutex> lk(event_mutex);
	events.push_back(e);
}

void TaikoHW::_process(double) {
	std::vector<Event> batch;
	{
		std::lock_guard<std::mutex> lk(event_mutex);
		batch.swap(events);
	}
	for (const Event &e : batch) {
		switch (e.type) {
			case 0: emit_signal("hit", e.slot, (int64_t)e.t, e.strength, e.kind, e.tracked, Vector2(e.x, e.y)); break;
			case 1: emit_signal("button", e.slot, (int64_t)e.buttons, (int64_t)e.pressed, (int64_t)e.released); break;
			case 2: emit_signal("controller_connected", e.slot); break;
			case 3: emit_signal("controller_disconnected", e.slot); break;
		}
	}
}

// ------------------------------------------------------------------------------------------
void TaikoHW::scan_loop() {
	int tick = 0;
	while (!scan_stop.load()) {
		reap_finished(false);
		if (tick % 15 == 0) open_new_devices(); // every ~1.5 s
		tick++;
		std::this_thread::sleep_for(std::chrono::milliseconds(100));
	}
}

void TaikoHW::open_new_devices() {
	std::vector<taiko::MoveDeviceEntry> found = taiko::enumerate_move_devices();
	for (const auto &entry : found) {
		bool known = false;
		int free_slot = -1;
		for (int i = 0; i < MAX_SLOTS; i++) {
			if (slots[i].connected.load() && slots[i].path == entry.path) known = true;
			if (!slots[i].connected.load() && !slots[i].is_virtual.load() && !slots[i].thread.joinable() && free_slot < 0) free_slot = i;
		}
		if (known || free_slot < 0) continue;
		// Re-enumerate to hand the full list to open() (needed on Windows for the sibling collection).
		hid_device_info *all = hid_enumerate(0x054c, entry.pid);
		const hid_device_info *info = nullptr;
		for (const hid_device_info *d = all; d; d = d->next) {
			if (d->path && entry.path == d->path) { info = d; break; }
		}
		if (!info) { hid_free_enumeration(all); continue; }
		std::unique_ptr<taiko::MoveDevice> dev(new taiko::MoveDevice(taiko_clock));
		bool ok = dev->open(info, all);
		hid_free_enumeration(all);
		if (!ok) continue;
		// Avoid duplicates by serial (Windows can expose a vanished device for a while).
		bool dup = false;
		for (int i = 0; i < MAX_SLOTS; i++) if (slots[i].connected.load() && slots[i].serial == dev->serial()) dup = true;
		if (dup) continue;
		Slot &s = slots[free_slot];
		s.path = entry.path;
		s.serial = dev->serial();
		s.model = (int)dev->model();
		s.bluetooth = dev->is_bluetooth();
		s.calibrated = dev->calibration().valid;
		s.device = std::move(dev);
		{
			std::lock_guard<std::mutex> lk(cfg_mutex);
			std::lock_guard<std::mutex> lk2(s.mtx);
			s.detector.set_config(default_cfg);
			s.detector.reset();
			s.buttons = 0; s.trigger = 0; s.battery = 0; s.reports = 0; s.period_us = 0;
		}
		s.led_dirty.store(true);
		s.stop_flag.store(false);
		s.finished.store(false);
		s.connected.store(true);
		s.thread = std::thread(&TaikoHW::reader_loop, this, free_slot);
		Event e; e.type = 2; e.slot = free_slot;
		push_event(e);
	}
}

void TaikoHW::reap_finished(bool join_all) {
	for (int i = 0; i < MAX_SLOTS; i++) {
		Slot &s = slots[i];
		if (s.thread.joinable() && (s.finished.load() || join_all)) {
			s.stop_flag.store(true);
			s.thread.join();
			s.device.reset();
			s.path.clear();
			s.connected.store(false);
		}
	}
}

void TaikoHW::close_slot(int i) {
	Slot &s = slots[i];
	s.stop_flag.store(true);
	if (s.thread.joinable()) s.thread.join();
	s.device.reset();
	s.path.clear();
	if (s.connected.exchange(false)) {
		Event e; e.type = 3; e.slot = i;
		push_event(e);
	}
}

void TaikoHW::emit_hit_for(int slot_index, const taiko::HitEvent &h) {
	Event e;
	e.type = 0;
	e.slot = slot_index;
	e.t = h.t_usec;
	e.strength = h.strength;
	e.kind = h.kind;
	Slot &s = slots[slot_index];
	if (s.is_virtual.load()) {
		e.tracked = s.debug_tracked;
		e.x = s.debug_x; e.y = s.debug_y;
	} else if (tracker && tracker->running()) {
		taiko::TrackResult r = tracker->get_result(slot_index);
		// Only trust positions from a recent frame (< 120 ms old).
		if (r.tracked && (h.t_usec - r.t_usec) < 120000 && (r.t_usec - h.t_usec) < 120000) {
			e.tracked = true;
			e.x = r.x; e.y = r.y;
		}
	}
	push_event(e);
}

void TaikoHW::reader_loop(int idx) {
	Slot &s = slots[idx];
	taiko::MoveDevice *dev = s.device.get();
	int64_t last_report = taiko_clock();
	int64_t last_led = 0;
	uint32_t prev_buttons = 0;
	int consecutive_errors = 0;
	while (!s.stop_flag.load()) {
		taiko::ImuSample samples[2];
		int n = dev->poll(4, samples);
		int64_t now = taiko_clock();
		if (n < 0) {
			consecutive_errors++;
			if (consecutive_errors > 20) break;
			std::this_thread::sleep_for(std::chrono::milliseconds(5));
			continue;
		}
		consecutive_errors = 0;
		if (n > 0) {
			last_report = now;
			uint32_t buttons = dev->buttons();
			taiko::HitEvent hit;
			bool fired = false;
			{
				std::lock_guard<std::mutex> lk(s.mtx);
				for (int k = 0; k < n; k++) {
					taiko::HitEvent h;
					if (s.detector.feed(samples[k], h)) { hit = h; fired = true; }
				}
				s.last_sample = samples[n - 1];
				s.buttons = buttons;
				s.trigger = dev->trigger();
				s.battery = dev->battery();
				s.period_us = dev->sample_period_us();
				s.reports = dev->report_count();
			}
			if (fired) emit_hit_for(idx, hit);
			if (buttons != prev_buttons) {
				Event e; e.type = 1; e.slot = idx; e.t = samples[n - 1].t_usec;
				e.buttons = buttons; e.pressed = buttons & ~prev_buttons; e.released = prev_buttons & ~buttons;
				push_event(e);
				prev_buttons = buttons;
			}
		} else if (now - last_report > 4000000) {
			break; // no reports for 4 s: controller went away
		}
		// LEDs: apply changes promptly (rate limited) and refresh periodically so the bulb stays lit.
		bool dirty = s.led_dirty.load();
		if ((dirty && now - last_led > 30000) || (now - last_led > 2000000)) {
			uint32_t rgb = s.led_rgb.load();
			if (dev->write_leds((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF, s.rumble.load())) {
				last_led = now;
				if (dirty) s.led_dirty.store(false);
			} else {
				last_led = now; // don't spam on failure
			}
		}
	}
	// Turn the light off when we leave (best effort).
	if (!s.stop_flag.load()) {
		s.connected.store(false);
		Event e; e.type = 3; e.slot = idx;
		push_event(e);
	}
	s.finished.store(true);
}

// ------------------------------------------------------------------------------------------
Dictionary TaikoHW::get_controller_info(int slot) {
	Dictionary d;
	if (slot < 0 || slot >= MAX_SLOTS) return d;
	Slot &s = slots[slot];
	bool connected = s.connected.load();
	d["connected"] = connected;
	d["virtual"] = s.is_virtual.load();
	d["serial"] = String(s.serial.c_str());
	d["model"] = s.model == 1 ? "ZCM2" : "ZCM1";
	d["bluetooth"] = s.bluetooth;
	d["calibrated"] = s.calibrated;
	uint8_t bat;
	{
		std::lock_guard<std::mutex> lk(s.mtx);
		bat = s.battery;
	}
	d["battery"] = (int)(bat <= 5 ? bat : 5);
	d["charging"] = (bat == 0xEE);
	d["charged"] = (bat == 0xEF);
	return d;
}

Dictionary TaikoHW::get_controller_live(int slot) {
	Dictionary d;
	if (slot < 0 || slot >= MAX_SLOTS) return d;
	Slot &s = slots[slot];
	std::lock_guard<std::mutex> lk(s.mtx);
	d["down_speed"] = s.detector.down_speed();
	d["last_peak"] = s.detector.last_peak();
	d["jerk"] = s.detector.last_jerk();
	d["armed"] = s.detector.armed();
	taiko::Vec3 u = s.detector.gravity_up();
	d["up"] = Vector3(u.x, u.y, u.z);
	d["accel"] = Vector3(s.last_sample.accel.x, s.last_sample.accel.y, s.last_sample.accel.z);
	d["gyro"] = Vector3(s.last_sample.gyro.x, s.last_sample.gyro.y, s.last_sample.gyro.z);
	d["t_usec"] = (int64_t)s.last_sample.t_usec;
	d["buttons"] = (int64_t)s.buttons;
	d["trigger"] = (int)s.trigger;
	d["period_us"] = s.period_us;
	d["reports"] = s.reports;
	if (tracker && tracker->running() && !s.is_virtual.load()) {
		taiko::TrackResult r = tracker->get_result(slot);
		d["tracked"] = r.tracked;
		d["pos"] = Vector2(r.x, r.y);
		d["radius"] = r.radius;
	} else {
		d["tracked"] = s.debug_tracked;
		d["pos"] = Vector2(s.debug_x, s.debug_y);
		d["radius"] = 0.0f;
	}
	return d;
}

Array TaikoHW::get_connected_slots() {
	Array a;
	for (int i = 0; i < MAX_SLOTS; i++) if (slots[i].connected.load()) a.push_back(i);
	return a;
}

void TaikoHW::set_led(int slot, const Color &c) {
	if (slot < 0 || slot >= MAX_SLOTS) return;
	uint32_t rgb = ((uint32_t)(CLAMP(c.r, 0.0f, 1.0f) * 255.0f + 0.5f) << 16) | ((uint32_t)(CLAMP(c.g, 0.0f, 1.0f) * 255.0f + 0.5f) << 8) | (uint32_t)(CLAMP(c.b, 0.0f, 1.0f) * 255.0f + 0.5f);
	if (slots[slot].led_rgb.exchange(rgb) != rgb) slots[slot].led_dirty.store(true);
}

void TaikoHW::set_rumble(int slot, float amount) {
	if (slot < 0 || slot >= MAX_SLOTS) return;
	uint8_t v = (uint8_t)(CLAMP(amount, 0.0f, 1.0f) * 255.0f + 0.5f);
	if (slots[slot].rumble.exchange(v) != v) slots[slot].led_dirty.store(true);
}

Dictionary TaikoHW::config_to_dict(const taiko::HitDetector::Config &c) {
	Dictionary d;
	d["mode"] = c.mode;
	d["trigger_point"] = c.trigger_point;
	d["threshold"] = c.threshold;
	d["min_peak"] = c.min_peak;
	d["peak_confirm_ratio"] = c.peak_confirm_ratio;
	d["jerk_threshold"] = c.jerk_threshold;
	d["refractory_ms"] = c.refractory_ms;
	d["max_stroke_ms"] = c.max_stroke_ms;
	d["gravity_gain"] = c.gravity_gain;
	d["rise_margin"] = c.rise_margin;
	d["stick_axis"] = Vector3(c.stick_axis.x, c.stick_axis.y, c.stick_axis.z);
	return d;
}

taiko::HitDetector::Config TaikoHW::dict_to_config(const Dictionary &d, const taiko::HitDetector::Config &base) {
	taiko::HitDetector::Config c = base;
	if (d.has("mode")) c.mode = (int)d["mode"];
	if (d.has("trigger_point")) c.trigger_point = (int)d["trigger_point"];
	if (d.has("threshold")) c.threshold = (float)(double)d["threshold"];
	if (d.has("min_peak")) c.min_peak = (float)(double)d["min_peak"];
	if (d.has("peak_confirm_ratio")) c.peak_confirm_ratio = (float)(double)d["peak_confirm_ratio"];
	if (d.has("jerk_threshold")) c.jerk_threshold = (float)(double)d["jerk_threshold"];
	if (d.has("refractory_ms")) c.refractory_ms = (float)(double)d["refractory_ms"];
	if (d.has("max_stroke_ms")) c.max_stroke_ms = (float)(double)d["max_stroke_ms"];
	if (d.has("gravity_gain")) c.gravity_gain = (float)(double)d["gravity_gain"];
	if (d.has("rise_margin")) c.rise_margin = (float)(double)d["rise_margin"];
	if (d.has("stick_axis")) {
		Vector3 v = d["stick_axis"];
		c.stick_axis = taiko::Vec3(v.x, v.y, v.z);
	}
	return c;
}

void TaikoHW::set_hit_config(const Dictionary &cfg, int slot) {
	std::lock_guard<std::mutex> lk(cfg_mutex);
	if (slot < 0) {
		default_cfg = dict_to_config(cfg, default_cfg);
		for (int i = 0; i < MAX_SLOTS; i++) {
			std::lock_guard<std::mutex> lk2(slots[i].mtx);
			slots[i].detector.set_config(default_cfg);
		}
	} else if (slot < MAX_SLOTS) {
		std::lock_guard<std::mutex> lk2(slots[slot].mtx);
		slots[slot].detector.set_config(dict_to_config(cfg, slots[slot].detector.config()));
	}
}

Dictionary TaikoHW::get_hit_config(int slot) {
	if (slot < 0 || slot >= MAX_SLOTS) {
		std::lock_guard<std::mutex> lk(cfg_mutex);
		return config_to_dict(default_cfg);
	}
	std::lock_guard<std::mutex> lk(slots[slot].mtx);
	return config_to_dict(slots[slot].detector.config());
}

void TaikoHW::reset_detector(int slot) {
	if (slot < 0 || slot >= MAX_SLOTS) return;
	std::lock_guard<std::mutex> lk(slots[slot].mtx);
	slots[slot].detector.reset();
}

// ------------------------------------------------------------------------------------------
int TaikoHW::camera_device_count() {
	return taiko::EyeTracker::device_count();
}
bool TaikoHW::camera_start(int fps, int width) {
	if (!tracker) return false;
	return tracker->start(width, width == 640 ? 480 : 240, fps);
}
void TaikoHW::camera_stop() { if (tracker) tracker->stop(); }
bool TaikoHW::camera_running() { return tracker && tracker->running(); }
void TaikoHW::camera_set_exposure(int v) { if (tracker) tracker->set_exposure(v); }
void TaikoHW::camera_set_gain(int v) { if (tracker) tracker->set_gain(v); }
void TaikoHW::camera_set_auto(bool on) { if (tracker) { tracker->set_auto_gain(on); tracker->set_auto_white_balance(on); } }
void TaikoHW::camera_set_flip(bool h, bool v) { if (tracker) tracker->set_flip(h, v); }

void TaikoHW::camera_set_target(int slot, float hue, float tol, float min_sat, float min_val, bool enabled) {
	if (!tracker) return;
	taiko::TrackTarget t;
	t.enabled = enabled; t.hue = hue; t.hue_tol = tol; t.min_sat = min_sat; t.min_val = min_val;
	tracker->set_target(slot, t);
}

Dictionary TaikoHW::camera_get_target(int slot) {
	Dictionary d;
	if (!tracker) return d;
	taiko::TrackTarget t = tracker->get_target(slot);
	d["enabled"] = t.enabled; d["hue"] = t.hue; d["tolerance"] = t.hue_tol; d["min_sat"] = t.min_sat; d["min_val"] = t.min_val;
	return d;
}

Dictionary TaikoHW::camera_get_result(int slot) {
	Dictionary d;
	if (!tracker) return d;
	taiko::TrackResult r = tracker->get_result(slot);
	d["tracked"] = r.tracked; d["pos"] = Vector2(r.x, r.y); d["radius"] = r.radius; d["pixels"] = r.pixels; d["t_usec"] = (int64_t)r.t_usec; d["frame"] = (int64_t)r.frame_id;
	return d;
}

Dictionary TaikoHW::camera_get_stats() {
	Dictionary d;
	if (!tracker) return d;
	taiko::CameraStats s = tracker->get_stats();
	d["running"] = s.running; d["width"] = s.width; d["height"] = s.height; d["fps_setting"] = s.fps_setting;
	d["fps"] = s.fps_measured; d["frames"] = (int64_t)s.frames; d["bright_pixels"] = s.bright_pixels; d["stray_bright"] = s.stray_bright;
	d["last_frame_t"] = (int64_t)s.last_frame_t; d["process_ms"] = s.process_ms;
	d["exposure"] = tracker->exposure(); d["gain"] = tracker->gain();
	return d;
}

void TaikoHW::camera_set_preview(bool on) { if (tracker) tracker->set_preview_enabled(on); }

Ref<Image> TaikoHW::camera_get_preview() {
	Ref<Image> img;
	if (!tracker) return img;
	std::vector<uint8_t> rgb;
	int w = 0, h = 0;
	if (!tracker->copy_preview(rgb, w, h) || w <= 0 || h <= 0) return img;
	PackedByteArray data;
	data.resize((int64_t)rgb.size());
	memcpy(data.ptrw(), rgb.data(), rgb.size());
	img = Image::create_from_data(w, h, false, Image::FORMAT_RGB8, data);
	return img;
}

Dictionary TaikoHW::camera_sample_color(float x, float y, float r) {
	Dictionary d;
	d["ok"] = false;
	if (!tracker) return d;
	float hue, sat, val;
	int count;
	if (tracker->sample_color(x, y, r, hue, sat, val, count)) {
		d["ok"] = true; d["hue"] = hue; d["sat"] = sat; d["val"] = val; d["count"] = count;
	}
	return d;
}

// ------------------------------------------------------------------------------------------
bool TaikoHW::pairing_supported() { return taiko::PairingSession::supported(); }
bool TaikoHW::is_elevated() { return taiko::PairingSession::is_elevated(); }

bool TaikoHW::pair_begin(int slot) {
	if (slot < 0 || slot >= MAX_SLOTS) return false;
	Slot &s = slots[slot];
	if (!s.connected.load() || !s.device) return false;
	// The reader thread owns the handle; pause it while we send feature reports.
	std::lock_guard<std::mutex> lk(s.mtx);
	return pairing.begin(s.device.get(), s.model);
}

Dictionary TaikoHW::pair_status() {
	taiko::PairingStatus st = pairing.status();
	Dictionary d;
	d["active"] = st.active; d["done"] = st.done; d["success"] = st.success; d["step"] = st.step;
	d["message"] = String(st.message.c_str());
	d["controller"] = String(st.controller_addr.c_str());
	d["host"] = String(st.host_addr.c_str());
	return d;
}

void TaikoHW::pair_cancel() { pairing.cancel(); }

// ------------------------------------------------------------------------------------------
void TaikoHW::debug_add_virtual(int slot) {
	if (slot < 0 || slot >= MAX_SLOTS) return;
	Slot &s = slots[slot];
	if (s.connected.load()) return;
	{
		std::lock_guard<std::mutex> lk(cfg_mutex);
		std::lock_guard<std::mutex> lk2(s.mtx);
		s.detector.set_config(default_cfg);
		s.detector.reset();
	}
	s.serial = "virtual-" + std::to_string(slot);
	s.model = 1;
	s.bluetooth = true;
	s.calibrated = true;
	s.is_virtual.store(true);
	s.connected.store(true);
	Event e; e.type = 2; e.slot = slot;
	push_event(e);
}

void TaikoHW::debug_remove_virtual(int slot) {
	if (slot < 0 || slot >= MAX_SLOTS) return;
	Slot &s = slots[slot];
	if (!s.is_virtual.load()) return;
	s.is_virtual.store(false);
	if (s.connected.exchange(false)) {
		Event e; e.type = 3; e.slot = slot;
		push_event(e);
	}
}

void TaikoHW::debug_inject(int slot, int64_t t_usec, const Vector3 &accel, const Vector3 &gyro) {
	if (slot < 0 || slot >= MAX_SLOTS) return;
	Slot &s = slots[slot];
	if (!s.is_virtual.load()) return;
	taiko::ImuSample smp;
	smp.t_usec = t_usec;
	smp.accel = taiko::Vec3(accel.x, accel.y, accel.z);
	smp.gyro = taiko::Vec3(gyro.x, gyro.y, gyro.z);
	taiko::HitEvent h;
	bool fired;
	{
		std::lock_guard<std::mutex> lk(s.mtx);
		fired = s.detector.feed(smp, h);
		s.last_sample = smp;
		s.reports++;
	}
	if (fired) emit_hit_for(slot, h);
}

void TaikoHW::debug_set_tracking(int slot, bool tracked, const Vector2 &pos) {
	if (slot < 0 || slot >= MAX_SLOTS) return;
	Slot &s = slots[slot];
	std::lock_guard<std::mutex> lk(s.mtx);
	s.debug_tracked = tracked;
	s.debug_x = pos.x;
	s.debug_y = pos.y;
}
