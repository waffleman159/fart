// Crash and repair detection, kept free of Windows and SDK calls so it can be tested natively
// (tests/test_plugin.cpp). Thresholds come from sheets/crash_rules.json via generated/sheet_data.h.
#pragma once
#include <deque>
#include <string>

namespace shadow {

struct Detection {
    enum Kind { none, crash, repair } kind = none;
    double impact_kmh = 0, peak_g = 0, damage_delta = 0, wear_total = 0;
    std::string trigger;
};

template <typename Rules>
class Detector {
public:
    void reset() { window_.clear(); min_wear_ = 0; last_crash_ = -1e9; }
    void restart_timer() { window_.clear(); }

    // now_s: simulation time; kmh: |speed|; g: acceleration magnitude in g; wear: summed wear 0..n;
    // fined_crash: ATS fined the player for a crash this frame.
    Detection update(double now_s, double kmh, double g, double wear, bool fined_crash) {
        Detection d;
        window_.push_back({now_s, kmh, g, wear});
        while (!window_.empty() && now_s - window_.front().t > Rules::window_s) window_.pop_front();

        // Repair: wear fell noticeably (service shop, or a different truck).
        if (wear + Rules::repair_drop < min_wear_) {
            d.kind = Detection::repair;
            d.wear_total = wear;
            min_wear_ = wear;
            window_.clear();
            return d;
        }
        if (wear > min_wear_) min_wear_ = wear;

        if (now_s - last_crash_ < Rules::cooldown_s || window_.size() < 2) return d;

        double max_kmh = 0, peak_g = 0;
        for (const Sample &s : window_) { if (s.kmh > max_kmh) max_kmh = s.kmh; if (s.g > peak_g) peak_g = s.g; }
        const double speed_drop = max_kmh - kmh;
        const double damage_delta = wear - window_.front().wear;
        const bool impact = speed_drop >= Rules::min_speed_drop_kmh || peak_g >= Rules::min_peak_g;
        const bool damaged = damage_delta >= Rules::min_damage_delta;
        if ((impact && damaged) || fined_crash) {
            d.kind = Detection::crash;
            d.impact_kmh = max_kmh;
            d.peak_g = peak_g;
            d.damage_delta = damage_delta;
            d.trigger = (impact && damaged) ? "physics" : "fine";
            last_crash_ = now_s;
        }
        return d;
    }

private:
    struct Sample { double t, kmh, g, wear; };
    std::deque<Sample> window_;
    double min_wear_ = 0;
    double last_crash_ = -1e9;
};

}  // namespace shadow
