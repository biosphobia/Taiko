// IMU-based drum hit detection for PS Move controllers.
// Platform independent, no Godot dependencies (unit-tested standalone).
#pragma once
#include <cstdint>
#include <cmath>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

namespace taiko {

struct Vec3 {
	float x = 0, y = 0, z = 0;
	Vec3() {}
	Vec3(float px, float py, float pz) : x(px), y(py), z(pz) {}
	Vec3 operator+(const Vec3 &o) const { return Vec3(x + o.x, y + o.y, z + o.z); }
	Vec3 operator-(const Vec3 &o) const { return Vec3(x - o.x, y - o.y, z - o.z); }
	Vec3 operator*(float s) const { return Vec3(x * s, y * s, z * s); }
	float dot(const Vec3 &o) const { return x * o.x + y * o.y + z * o.z; }
	Vec3 cross(const Vec3 &o) const { return Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x); }
	float length() const { return std::sqrt(x * x + y * y + z * z); }
	Vec3 normalized() const {
		float l = length();
		return l > 1e-6f ? (*this) * (1.0f / l) : Vec3(0, 1, 0);
	}
};

struct ImuSample {
	int64_t t_usec = 0; // monotonic host time of the sample
	Vec3 accel; // in g
	Vec3 gyro; // in rad/s
};

struct HitEvent {
	int64_t t_usec = 0; // estimated moment of impact
	float strength = 0; // peak down-speed (rad/s) or jerk (g) for surface hits
	int kind = 0; // 0 = air (peak), 1 = surface (jerk), 2 = early (threshold crossing)
};

class HitDetector {
public:
	enum Mode { MODE_AIR = 0, MODE_SURFACE = 1, MODE_HYBRID = 2 };
	enum TriggerPoint { TRIGGER_PEAK = 0, TRIGGER_EARLY = 1 };

	struct Config {
		int mode = MODE_AIR;
		int trigger_point = TRIGGER_PEAK;
		float threshold = 4.0f; // rad/s: down-speed needed to arm a stroke
		float min_peak = 5.0f; // rad/s: strokes peaking below this are ignored
		float peak_confirm_ratio = 0.92f; // fire once speed falls to this fraction of the running peak
		float jerk_threshold = 2.0f; // g change between consecutive samples (surface mode)
		float refractory_ms = 50.0f; // minimum time between two hits from the same controller
		float rise_margin = 2.0f; // rad/s the speed must rise above its recent valley before a new stroke can arm
		float max_stroke_ms = 350.0f; // an armed stroke that never peaks is abandoned after this
		float gravity_gain = 0.03f; // complementary filter gain toward accelerometer
		Vec3 stick_axis = Vec3(0, 1, 0); // controller axis pointing at the bulb
	};

	HitDetector();
	void set_config(const Config &c);
	const Config &config() const { return cfg; }
	void reset();

	// Feed one IMU sample (samples must be in chronological order). Returns true when a hit fired.
	bool feed(const ImuSample &s, HitEvent &out);

	// Live values (for calibration UI)
	float down_speed() const { return last_speed; }
	float last_peak() const { return last_fired_peak; }
	float last_jerk() const { return last_jerk_value; }
	Vec3 gravity_up() const { return up; } // unit vector pointing up, in sensor frame
	bool armed() const { return state == ARMED; }

private:
	enum State { IDLE, ARMED, REFRACTORY };
	Config cfg;
	State state = IDLE;
	bool have_prev = false;
	int64_t prev_t = 0;
	Vec3 prev_accel;
	Vec3 up = Vec3(0, 1, 0);
	bool up_initialized = false;
	float last_speed = 0;
	float last_jerk_value = 0;
	float last_fired_peak = 0;
	float peak = 0;
	float valley = 0; // lowest speed seen since the last fire (or since the last abandoned stroke)
	float prev_speed = 0;
	int64_t peak_t = 0;
	int64_t arm_t = 0;
	int64_t refractory_until = 0;
	int64_t last_stroke_t = -1; // last time we saw significant down-speed (for surface gating)

	void fire(HitEvent &out, int64_t t, float strength, int kind);
};

} // namespace taiko
