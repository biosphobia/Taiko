#include "eye_tracker.h"
#include "ps3eye.h"
#include <cmath>
#include <cstring>
#include <algorithm>
#include <chrono>

namespace taiko {

void rgb_to_hsv(uint8_t r, uint8_t g, uint8_t b, float &h, float &s, float &v) {
	int mx = std::max(r, std::max(g, b));
	int mn = std::min(r, std::min(g, b));
	v = mx / 255.0f;
	int d = mx - mn;
	s = (mx > 0) ? (float)d / (float)mx : 0.0f;
	if (d == 0) { h = 0.0f; return; }
	float hh;
	if (mx == r) hh = (float)(g - b) / (float)d;
	else if (mx == g) hh = 2.0f + (float)(b - r) / (float)d;
	else hh = 4.0f + (float)(r - g) / (float)d;
	hh *= 60.0f;
	if (hh < 0.0f) hh += 360.0f;
	h = hh;
}

static inline float hue_dist(float a, float b) {
	float d = std::fabs(a - b);
	while (d > 360.0f) d -= 360.0f;
	return d > 180.0f ? 360.0f - d : d;
}

EyeTracker::EyeTracker(ClockFn clock) : now(clock) {}
EyeTracker::~EyeTracker() { stop(); }

int EyeTracker::device_count() {
	const auto &devs = ps3eye::PS3EYECam::getDevices(true);
	return (int)devs.size();
}

bool EyeTracker::start(int w, int h, int f) {
	stop();
	const auto &devs = ps3eye::PS3EYECam::getDevices(true);
	if (devs.empty()) return false;
	cam = devs[0];
	width = (w == 640) ? 640 : 320;
	height = (width == 640) ? 480 : 240;
	fps = f;
	if (!cam->init((uint32_t)width, (uint32_t)height, (uint16_t)fps, ps3eye::PS3EYECam::EOutputFormat::RGB)) {
		cam.reset();
		return false;
	}
	width = (int)cam->getWidth();
	height = (int)cam->getHeight();
	fps = (int)cam->getFrameRate();
	frame_buf.assign((size_t)width * height * 3, 0);
	cls.assign((size_t)width * height, 0);
	labels.assign((size_t)width * height, 0);
	cam->setAutogain(false);
	cam->setAutoWhiteBalance(false);
	cam->setExposure((uint8_t)cur_exposure);
	cam->setGain((uint8_t)cur_gain);
	cam->start();
	{
		std::lock_guard<std::mutex> lk(result_mutex);
		stats = CameraStats();
		stats.running = true;
		stats.width = width;
		stats.height = height;
		stats.fps_setting = fps;
		for (auto &r : results) r = TrackResult();
	}
	stop_requested.store(false);
	is_running.store(true);
	worker = std::thread(&EyeTracker::loop, this);
	return true;
}

void EyeTracker::stop() {
	if (!cam && !worker.joinable()) return;
	stop_requested.store(true);
	if (cam) cam->stop(); // unblocks getFrame
	if (worker.joinable()) worker.join();
	is_running.store(false);
	cam.reset();
	std::lock_guard<std::mutex> lk(result_mutex);
	stats.running = false;
}

void EyeTracker::set_exposure(int v) { cur_exposure = std::min(std::max(v, 0), 255); if (cam) cam->setExposure((uint8_t)cur_exposure); }
void EyeTracker::set_gain(int v) { cur_gain = std::min(std::max(v, 0), 63); if (cam) cam->setGain((uint8_t)cur_gain); }
void EyeTracker::set_auto_gain(bool on) { if (cam) cam->setAutogain(on); }
void EyeTracker::set_auto_white_balance(bool on) { if (cam) cam->setAutoWhiteBalance(on); }
void EyeTracker::set_flip(bool h, bool v) { if (cam) cam->setFlip(h, v); }

void EyeTracker::set_target(int idx, const TrackTarget &t) {
	if (idx < 0 || idx >= MAX_TRACK_TARGETS) return;
	std::lock_guard<std::mutex> lk(target_mutex);
	targets[idx] = t;
}
TrackTarget EyeTracker::get_target(int idx) {
	if (idx < 0 || idx >= MAX_TRACK_TARGETS) return TrackTarget();
	std::lock_guard<std::mutex> lk(target_mutex);
	return targets[idx];
}
TrackResult EyeTracker::get_result(int idx) {
	if (idx < 0 || idx >= MAX_TRACK_TARGETS) return TrackResult();
	std::lock_guard<std::mutex> lk(result_mutex);
	return results[idx];
}
CameraStats EyeTracker::get_stats() {
	std::lock_guard<std::mutex> lk(result_mutex);
	return stats;
}

bool EyeTracker::copy_preview(std::vector<uint8_t> &rgb, int &w, int &h) {
	std::lock_guard<std::mutex> lk(frame_mutex);
	if (preview.empty()) return false;
	rgb = preview;
	w = width;
	h = height;
	return true;
}

bool EyeTracker::sample_color(float cx, float cy, float r, float &hue, float &sat, float &val, int &count) {
	std::lock_guard<std::mutex> lk(frame_mutex);
	if (latest.empty()) return false;
	// Circular mean of hue over bright saturated pixels in the circle.
	double sx = 0, sy = 0, ssat = 0, sval = 0;
	count = 0;
	int x0 = std::max(0, (int)(cx - r)), x1 = std::min(width - 1, (int)(cx + r));
	int y0 = std::max(0, (int)(cy - r)), y1 = std::min(height - 1, (int)(cy + r));
	for (int y = y0; y <= y1; y++) {
		for (int x = x0; x <= x1; x++) {
			float dx = x - cx, dy = y - cy;
			if (dx * dx + dy * dy > r * r) continue;
			const uint8_t *p = &latest[((size_t)y * width + x) * 3];
			float h, s, v;
			rgb_to_hsv(p[0], p[1], p[2], h, s, v);
			if (v < 0.3f || s < 0.3f) continue;
			double a = h * M_PI / 180.0;
			sx += std::cos(a); sy += std::sin(a); ssat += s; sval += v; count++;
		}
	}
	if (count < 5) return false;
	double a = std::atan2(sy, sx) * 180.0 / M_PI;
	if (a < 0) a += 360.0;
	hue = (float)a;
	sat = (float)(ssat / count);
	val = (float)(sval / count);
	return true;
}

void EyeTracker::loop() {
	int64_t last_fps_t = now();
	int fps_frames = 0;
	while (!stop_requested.load()) {
		if (!cam || !cam->isStreaming()) break;
		cam->getFrame(frame_buf.data());
		if (stop_requested.load()) break;
		int64_t t = now();
		// The frame was exposed roughly one frame period before it was delivered.
		int64_t t_frame = t - (int64_t)(1000000.0 / std::max(1, fps));
		auto c0 = std::chrono::steady_clock::now();
		process_frame(frame_buf.data(), t_frame);
		auto c1 = std::chrono::steady_clock::now();
		float pms = std::chrono::duration<float, std::milli>(c1 - c0).count();
		fps_frames++;
		{
			std::lock_guard<std::mutex> lk(result_mutex);
			stats.frames++;
			stats.last_frame_t = t;
			stats.process_ms = pms;
			if (t - last_fps_t >= 1000000) {
				stats.fps_measured = (float)fps_frames * 1e6f / (float)(t - last_fps_t);
				fps_frames = 0;
				last_fps_t = t;
			}
		}
		{
			std::lock_guard<std::mutex> lk(frame_mutex);
			latest.assign(frame_buf.begin(), frame_buf.end());
			if (preview_enabled.load()) preview = latest;
		}
	}
	is_running.store(false);
}

static inline int32_t uf_find(std::vector<int32_t> &parent, int32_t x) {
	while (parent[x] != x) {
		parent[x] = parent[parent[x]];
		x = parent[x];
	}
	return x;
}

void EyeTracker::process_frame(const uint8_t *rgb, int64_t t) {
	TrackTarget tg[MAX_TRACK_TARGETS];
	{
		std::lock_guard<std::mutex> lk(target_mutex);
		for (int i = 0; i < MAX_TRACK_TARGETS; i++) tg[i] = targets[i];
	}
	const int W = width, H = height, N = W * H;
	int bright = 0;
	// 1) classify pixels
	int min_val_thresh = 255;
	for (int i = 0; i < MAX_TRACK_TARGETS; i++) if (tg[i].enabled) min_val_thresh = std::min(min_val_thresh, (int)(tg[i].min_val * 255.0f));
	for (int i = 0; i < N; i++) {
		const uint8_t *p = rgb + (size_t)i * 3;
		int mx = std::max(p[0], std::max(p[1], p[2]));
		if (mx >= 235) bright++;
		uint8_t c = 0;
		if (mx >= min_val_thresh) {
			float h, s, v;
			rgb_to_hsv(p[0], p[1], p[2], h, s, v);
			for (int k = 0; k < MAX_TRACK_TARGETS; k++) {
				if (!tg[k].enabled) continue;
				if (v >= tg[k].min_val && s >= tg[k].min_sat && hue_dist(h, tg[k].hue) <= tg[k].hue_tol) { c = (uint8_t)(k + 1); break; }
			}
		}
		cls[i] = c;
	}
	// 2) connected components (4-connectivity), union-find
	parent.clear();
	parent.push_back(0); // label 0 = background
	std::fill(labels.begin(), labels.end(), 0);
	for (int y = 0; y < H; y++) {
		for (int x = 0; x < W; x++) {
			int i = y * W + x;
			uint8_t c = cls[i];
			if (!c) continue;
			int32_t left = (x > 0 && cls[i - 1] == c) ? labels[i - 1] : 0;
			int32_t up = (y > 0 && cls[i - W] == c) ? labels[i - W] : 0;
			if (!left && !up) {
				int32_t l = (int32_t)parent.size();
				parent.push_back(l);
				labels[i] = l;
			} else if (left && up) {
				int32_t a = uf_find(parent, left), b = uf_find(parent, up);
				if (a != b) parent[std::max(a, b)] = std::min(a, b);
				labels[i] = std::min(a, b);
			} else {
				labels[i] = left ? left : up;
			}
		}
	}
	struct Blob { int count = 0; int minx = 1 << 30, maxx = -1, miny = 1 << 30, maxy = -1; double sx = 0, sy = 0; uint8_t c = 0; };
	std::vector<Blob> blobs(parent.size());
	for (int y = 0; y < H; y++) {
		for (int x = 0; x < W; x++) {
			int i = y * W + x;
			if (!labels[i]) continue;
			int32_t r = uf_find(parent, labels[i]);
			labels[i] = r;
			Blob &b = blobs[r];
			b.count++;
			b.minx = std::min(b.minx, x); b.maxx = std::max(b.maxx, x);
			b.miny = std::min(b.miny, y); b.maxy = std::max(b.maxy, y);
			b.sx += x; b.sy += y;
			b.c = cls[i];
		}
	}
	// 3) largest blob per target
	TrackResult res[MAX_TRACK_TARGETS];
	int best[MAX_TRACK_TARGETS] = { -1, -1, -1, -1 };
	for (size_t l = 1; l < blobs.size(); l++) {
		const Blob &b = blobs[l];
		if (b.count < 6) continue;
		int k = b.c - 1;
		if (k < 0 || k >= MAX_TRACK_TARGETS) continue;
		if (best[k] < 0 || blobs[best[k]].count < b.count) best[k] = (int)l;
	}
	for (int k = 0; k < MAX_TRACK_TARGETS; k++) {
		res[k].t_usec = t;
		if (best[k] >= 0) {
			const Blob &b = blobs[best[k]];
			res[k].tracked = true;
			// Bounding-box center is robust to the over-exposed white core of the sphere.
			res[k].x = 0.5f * (b.minx + b.maxx);
			res[k].y = 0.5f * (b.miny + b.maxy);
			res[k].radius = 0.5f * std::max(b.maxx - b.minx + 1, b.maxy - b.miny + 1);
			res[k].pixels = b.count;
		}
	}
	// 4) stray bright pixels: near-saturated pixels outside any tracked blob box (+margin)
	int stray = 0;
	if (bright > 0) {
		for (int y = 0; y < H; y += 2) {
			for (int x = 0; x < W; x += 2) {
				const uint8_t *p = rgb + ((size_t)y * W + x) * 3;
				int mx = std::max(p[0], std::max(p[1], p[2]));
				if (mx < 235) continue;
				bool inside = false;
				for (int k = 0; k < MAX_TRACK_TARGETS && !inside; k++) {
					if (!res[k].tracked) continue;
					float m = res[k].radius + 4.0f;
					if (std::fabs(x - res[k].x) <= m && std::fabs(y - res[k].y) <= m) inside = true;
				}
				if (!inside) stray++;
			}
		}
		stray *= 4; // sampled every other pixel in both directions
	}
	std::lock_guard<std::mutex> lk(result_mutex);
	for (int k = 0; k < MAX_TRACK_TARGETS; k++) {
		res[k].frame_id = stats.frames + 1;
		results[k] = res[k];
	}
	stats.bright_pixels = bright;
	stats.stray_bright = stray;
}

} // namespace taiko
