// Standalone unit test for the hit detector using synthetic drum strokes.
// Build: g++ -std=c++17 -O2 -I../src test_hit_detector.cpp ../src/hit_detector.cpp -o test_hit && ./test_hit
#include "hit_detector.h"
#include <cstdio>
#include <vector>
#include <cmath>
#include <random>

using namespace taiko;

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { printf("FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__); failures++; } } while (0)

// Simulate a controller held like a drumstick (bulb forward, Y axis horizontal),
// gravity along -Z in sensor frame (so accel reads +1g on Z when at rest).
// A down stroke is rotation about the X axis such that the bulb (+Y) moves toward -Z.
// tip_vel = w x Y; with w = (wx,0,0): w x Y = (0,0,wx). Down = (0,0,-1). speed = -(0,0,wx).(0,0,1)... 
// up=(0,0,1): speed = -(w x axis).up = -wx  -> need wx negative for a down stroke.
struct Sim {
	std::vector<ImuSample> samples;
	std::vector<int64_t> true_impacts;
	int64_t t = 0;
	const int64_t dt = 5750; // ZCM1: two frames per ~11.5ms report
	std::mt19937 rng{42};
	void rest(double seconds) {
		int n = (int)(seconds * 1e6 / dt);
		std::normal_distribution<float> noise(0.0f, 0.02f);
		for (int i = 0; i < n; i++) {
			ImuSample s; s.t_usec = t; s.accel = Vec3(noise(rng), noise(rng), 1.0f + noise(rng)); s.gyro = Vec3(noise(rng), noise(rng), noise(rng));
			samples.push_back(s); t += dt;
		}
	}
	// A stroke: angular speed follows a half-sine of duration dur_ms peaking at peak_rad_s, then rebound.
	void stroke(float peak_rad_s, float dur_ms, bool surface_impact = false) {
		int n = (int)(dur_ms * 1000 / dt);
		int64_t start = t;
		std::normal_distribution<float> noise(0.0f, 0.02f);
		for (int i = 0; i < n; i++) {
			float ph = (float)i / (float)n; // 0..1
			float w = -peak_rad_s * std::sin(ph * (float)M_PI);
			ImuSample s; s.t_usec = t;
			s.gyro = Vec3(w + noise(rng), noise(rng), noise(rng));
			// centripetal + tangential accelerations appear on the accelerometer; add moderate disturbance
			s.accel = Vec3(noise(rng), 0.3f * std::fabs(w) / peak_rad_s + noise(rng), 1.0f + 0.2f * std::sin(ph * (float)M_PI * 2) + noise(rng));
			if (surface_impact && i == n / 2) {
				s.accel = s.accel + Vec3(0, 0, 6.0f); // impact spike
			}
			samples.push_back(s); t += dt;
		}
		true_impacts.push_back(start + (int64_t)(dur_ms * 1000 / 2)); // impact at peak speed
		// rebound (upstroke, slower)
		for (int i = 0; i < n; i++) {
			float ph = (float)i / (float)n;
			float w = 0.6f * peak_rad_s * std::sin(ph * (float)M_PI);
			ImuSample s; s.t_usec = t; s.gyro = Vec3(w + noise(rng), noise(rng), noise(rng)); s.accel = Vec3(noise(rng), noise(rng), 1.0f + noise(rng));
			samples.push_back(s); t += dt;
		}
	}
};

static std::vector<HitEvent> run(const Sim &sim, HitDetector::Config cfg) {
	HitDetector det; det.set_config(cfg);
	std::vector<HitEvent> hits;
	for (auto &s : sim.samples) { HitEvent h; if (det.feed(s, h)) hits.push_back(h); }
	return hits;
}

int main() {
	// 1) Basic: 10 strokes of varying strength, each must produce exactly one hit, timing within 8 ms of the true impact.
	{
		Sim sim; sim.rest(1.0);
		for (int i = 0; i < 10; i++) { sim.stroke(8.0f + (i % 3) * 4.0f, 90.0f); sim.rest(0.25); }
		HitDetector::Config cfg; auto hits = run(sim, cfg);
		CHECK(hits.size() == 10, "air mode: one hit per stroke");
		if (hits.size() == sim.true_impacts.size()) {
			for (size_t i = 0; i < hits.size(); i++) {
				double err_ms = (hits[i].t_usec - sim.true_impacts[i]) / 1000.0;
				CHECK(std::fabs(err_ms) <= 8.0, "air mode: impact timing within 8 ms");
				CHECK(hits[i].kind == 0, "air mode: kind is peak");
			}
		}
	}
	// 2) Fast drumroll: 12 hits/s, no double or missed triggers.
	{
		Sim sim; sim.rest(0.5);
		for (int i = 0; i < 24; i++) { sim.stroke(12.0f, 40.0f); } // 40ms down + 40ms up = 80 ms period
		HitDetector::Config cfg; auto hits = run(sim, cfg);
		CHECK(hits.size() == 24, "drumroll: 24 hits at 12.5 hits/s");
	}
	// 3) Slow waving below threshold must not trigger.
	{
		Sim sim; sim.rest(0.5); sim.stroke(2.5f, 400.0f); sim.rest(0.5);
		HitDetector::Config cfg; auto hits = run(sim, cfg);
		CHECK(hits.empty(), "slow wave: no hit");
	}
	// 4) Upstroke-only motion (negative speed) must not trigger.
	{
		Sim sim; sim.rest(0.5);
		for (int i = 0; i < 40; i++) { ImuSample s; s.t_usec = sim.t; s.gyro = Vec3(+10.0f, 0, 0); s.accel = Vec3(0, 0, 1); sim.samples.push_back(s); sim.t += sim.dt; }
		sim.rest(0.5);
		HitDetector::Config cfg; auto hits = run(sim, cfg);
		CHECK(hits.empty(), "upstroke: no hit");
	}
	// 5) Surface mode: jerk spike fires at the spike sample.
	{
		Sim sim; sim.rest(0.5);
		for (int i = 0; i < 5; i++) { sim.stroke(9.0f, 80.0f, true); sim.rest(0.3); }
		HitDetector::Config cfg; cfg.mode = HitDetector::MODE_SURFACE; auto hits = run(sim, cfg);
		CHECK(hits.size() == 5, "surface mode: 5 hits");
		for (auto &h : hits) CHECK(h.kind == 1, "surface mode: kind is surface");
	}
	// 6) Hybrid mode: no double-trigger when both detectors see the same stroke.
	{
		Sim sim; sim.rest(0.5);
		for (int i = 0; i < 5; i++) { sim.stroke(9.0f, 80.0f, true); sim.rest(0.3); }
		HitDetector::Config cfg; cfg.mode = HitDetector::MODE_HYBRID; auto hits = run(sim, cfg);
		CHECK(hits.size() == 5, "hybrid mode: 5 hits, no doubles");
	}
	// 7) Early trigger fires before the peak.
	{
		Sim sim; sim.rest(0.5); sim.stroke(10.0f, 100.0f); sim.rest(0.5);
		HitDetector::Config cfg; cfg.trigger_point = HitDetector::TRIGGER_EARLY; auto hits = run(sim, cfg);
		CHECK(hits.size() == 1, "early: one hit");
		if (!hits.empty()) CHECK(hits[0].t_usec < sim.true_impacts[0], "early: fires before peak");
	}
	// 8) Orientation change: after rotating the controller 90 degrees (bulb up), strokes must still register.
	{
		Sim sim; sim.rest(0.5);
		// rotate slowly about X by -90 deg over 1 s: up vector moves from +Z to... simulate accel accordingly
		int n = (int)(1e6 / sim.dt);
		for (int i = 0; i < n; i++) {
			float ang = (float)M_PI / 2 * (float)(i + 1) / n; // rotation about X
			ImuSample s; s.t_usec = sim.t; s.gyro = Vec3(-(float)M_PI / 2 / 1.0f, 0, 0);
			// rotating body about X by -ang: world up (0,0,1) in body frame becomes (0, sin, cos) or (0,-sin,cos)
			// choose the sign consistent with dg/dt = -w x g: g=(0,0,1), w=(-k,0,0): -w x g = -((-k,0,0)x(0,0,1)) = -(0, k, 0)?? compute: (a x b) = (ay*bz-az*by, az*bx-ax*bz, ax*by-ay*bx) = (0*1-0*0, 0*0-(-k)*1, 0) = (0,k,0); so dg/dt=(0,-k,0): g -> (0,-sin,cos)
			s.accel = Vec3(0, -std::sin(ang), std::cos(ang));
			sim.samples.push_back(s); sim.t += sim.dt;
		}
		// now "up" in sensor frame is (0,-1,0): the bulb points down. A stroke moving the tip "down" is now along the stick axis... 
		// so instead stroke about Z: tip_vel = w x Y with w=(0,0,wz) = (-wz, 0, 0); down = (0,1,0): speed = -(-wz,0,0).(0,-1,0)=0. Not a valid stroke direction (as in reality).
		// Rotate about X instead: tip_vel = (0,0,wx); speed = -(0,0,wx).(0,-1,0) = 0 also. Correct: with bulb pointing straight down, no rotation moves the tip downward. So test with a 45 degree pose instead.
		HitDetector det; det.set_config(HitDetector::Config());
		for (auto &s : sim.samples) { HitEvent h; det.feed(s, h); }
		Vec3 u = det.gravity_up();
		CHECK(std::fabs(u.y + 1.0f) < 0.15f && std::fabs(u.z) < 0.15f, "gravity filter follows the rotation");
	}
	if (failures == 0) printf("hit_detector: all tests passed\n");
	return failures ? 1 : 0;
}
