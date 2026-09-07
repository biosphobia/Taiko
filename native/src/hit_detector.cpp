#include "hit_detector.h"
#include <algorithm>

namespace taiko {

HitDetector::HitDetector() { reset(); }

void HitDetector::set_config(const Config &c) {
	cfg = c;
	if (cfg.stick_axis.length() < 1e-3f) cfg.stick_axis = Vec3(0, 1, 0);
	cfg.stick_axis = cfg.stick_axis.normalized();
	cfg.peak_confirm_ratio = std::min(std::max(cfg.peak_confirm_ratio, 0.5f), 0.99f);
	cfg.gravity_gain = std::min(std::max(cfg.gravity_gain, 0.001f), 0.5f);
}

void HitDetector::reset() {
	state = IDLE;
	have_prev = false;
	up_initialized = false;
	up = Vec3(0, 1, 0);
	last_speed = 0;
	last_jerk_value = 0;
	peak = 0;
	valley = 0;
	prev_speed = 0;
	peak_t = 0;
	arm_t = 0;
	refractory_until = 0;
	last_stroke_t = -1;
}

void HitDetector::fire(HitEvent &out, int64_t t, float strength, int kind) {
	out.t_usec = t;
	out.strength = strength;
	out.kind = kind;
	last_fired_peak = strength;
	state = REFRACTORY;
	refractory_until = std::max(t, prev_t) + (int64_t)(cfg.refractory_ms * 1000.0f);
	valley = last_speed;
}

bool HitDetector::feed(const ImuSample &s, HitEvent &out) {
	const int64_t t = s.t_usec;
	float dt = 0.0f;
	if (have_prev) {
		dt = (float)(t - prev_t) * 1e-6f;
		if (dt < 0.0f) dt = 0.0f;
		if (dt > 0.05f) dt = 0.05f; // clamp gaps (e.g. after a stall) to keep integration sane
	}

	// --- Gravity estimate in sensor frame (complementary filter on the "up" vector) ---
	// A world-fixed vector g expressed in a body rotating with angular velocity w evolves as dg/dt = -w x g.
	float a_len = s.accel.length();
	if (!up_initialized) {
		if (a_len > 0.3f) {
			up = s.accel.normalized();
			up_initialized = true;
		}
	} else {
		if (dt > 0.0f) {
			Vec3 d = s.gyro.cross(up) * (-dt);
			up = (up + d).normalized();
		}
		if (a_len > 0.3f) {
			// Trust the accelerometer more when it reads close to 1g (little linear acceleration).
			float dev = std::fabs(a_len - 1.0f);
			float trust = std::exp(-(dev * dev) / (2.0f * 0.25f * 0.25f));
			float gain = cfg.gravity_gain * trust;
			Vec3 meas = s.accel.normalized();
			up = (up * (1.0f - gain) + meas * gain).normalized();
		}
	}

	// --- Down-speed of the bulb: velocity of the stick tip due to rotation, projected on "down" ---
	// tip velocity direction (per unit stick length) = w x axis; down = -up.
	Vec3 tip_vel = s.gyro.cross(cfg.stick_axis);
	float speed = -tip_vel.dot(up);
	last_speed = speed;

	// --- Jerk (surface impact detector) ---
	float jerk = 0.0f;
	if (have_prev) {
		jerk = (s.accel - prev_accel).length();
	}
	last_jerk_value = jerk;

	bool fired = false;
	const bool air_enabled = (cfg.mode == MODE_AIR || cfg.mode == MODE_HYBRID);
	const bool surface_enabled = (cfg.mode == MODE_SURFACE || cfg.mode == MODE_HYBRID);

	if (speed > cfg.threshold * 0.5f) {
		last_stroke_t = t;
	}
	if (speed < valley) {
		valley = speed;
	}

	if (state == REFRACTORY && t >= refractory_until) {
		state = IDLE; // fall through to arming on this same sample
	}
	switch (state) {
		case REFRACTORY: {
			break;
		}
		case IDLE: {
			// A new stroke must rise clearly out of the recent valley: this rejects the decaying
			// tail of the previous stroke (which is still above threshold but falling).
			if (speed > cfg.threshold && (speed - valley) > cfg.rise_margin && speed > prev_speed) {
				state = ARMED;
				peak = speed;
				peak_t = t;
				arm_t = t;
				if (air_enabled && cfg.trigger_point == TRIGGER_EARLY) {
					fire(out, t, speed, 2);
					fired = true;
				}
			}
			break;
		}
		case ARMED: {
			if (speed > peak) {
				peak = speed;
				peak_t = t;
			} else if (air_enabled && (speed <= peak * cfg.peak_confirm_ratio || speed < cfg.threshold)) {
				// The stroke has passed its fastest point: that is the impact moment.
				if (peak >= cfg.min_peak) {
					fire(out, peak_t, peak, 0);
					fired = true;
				} else {
					state = IDLE;
					valley = speed;
				}
			} else if (!air_enabled && speed < cfg.threshold) {
				state = IDLE;
			}
			if (state == ARMED && (t - arm_t) > (int64_t)(cfg.max_stroke_ms * 1000.0f)) {
				state = IDLE; // slow wave, not a hit
				valley = speed; // require a fresh rise before arming again
			}
			break;
		}
	}

	// Surface impact: a sharp accelerometer discontinuity during/after a down stroke.
	if (!fired && surface_enabled && state != REFRACTORY && have_prev && jerk > cfg.jerk_threshold) {
		bool in_stroke = (last_stroke_t >= 0) && (t - last_stroke_t) < 150000;
		if (in_stroke) {
			fire(out, t, std::max(jerk, peak), 1);
			fired = true;
		}
	}

	have_prev = true;
	prev_t = t;
	prev_accel = s.accel;
	prev_speed = speed;
	return fired;
}

} // namespace taiko
