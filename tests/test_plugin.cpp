// Native test of the ATS plugin's sheet-generated code and crash detector (no game, no Windows).
// Build + run: tests/run_tests.sh
#include <cassert>
#include <cstdio>
#include <iostream>
#include <string>

#include "scssdk_telemetry.h"
#include "../ats_plugin/generated/sheet_data.h"
#include "../ats_plugin/src/crash_detector.h"

using shadow::Detection;
static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { std::fprintf(stderr, "FAIL %s:%d %s\n", __FILE__, __LINE__, #cond); ++failures; } } while (0)

static scs_named_value_t attr_str(const char *name, const char *v) {
    scs_named_value_t a{}; a.name = name; a.index = SCS_U32_NIL; a.value.type = SCS_VALUE_TYPE_string; a.value.value_string.value = v; return a;
}
static scs_named_value_t attr_float(const char *name, float v) {
    scs_named_value_t a{}; a.name = name; a.index = SCS_U32_NIL; a.value.type = SCS_VALUE_TYPE_float; a.value.value_float.value = v; return a;
}

int main() {
    // configuration: job cargo
    sheet::State s;
    scs_named_value_t job[] = {attr_str("cargo", "Lumber \"premium\""), attr_float("cargo.mass", 18143.7f), {}};
    sheet::apply_configuration("job", job, s);
    CHECK(s.cargo_name == "Lumber \"premium\"");
    CHECK(s.cargo_mass > 18143.0f && s.cargo_mass < 18144.0f);
    scs_named_value_t empty[] = {{}};
    sheet::apply_configuration("job", empty, s);            // job ended -> cleared
    CHECK(s.cargo_name.empty() && s.cargo_mass == 0.0f);
    sheet::apply_configuration("job", job, s);
    scs_named_value_t fine[] = {attr_str("fine.offence", "crash"), {}};
    sheet::apply_gameplay("player.fined", fine, s);
    CHECK(s.fine_offence == "crash");

    // encoders: print one of each for the JSON check in run_tests.sh
    s.speed = 25.0f; s.trailer_attached = true; s.truck_brand = "Peterbilt";
    sheet::Computed c; c.paused = false;
    std::cout << sheet::encode_tick(s, c) << "\n";
    c.impact_kmh = 88.2; c.peak_g = 3.1; c.damage_delta = 0.07; c.trigger = "physics";
    std::cout << sheet::encode_crash(s, c) << "\n";
    c.wear_total = 0.01;
    std::cout << sheet::encode_repair(s, c) << "\n";

    // detector scenarios at 60 fps
    const double dt = 1.0 / 60;
    {   // steady cruise, no damage: nothing
        shadow::Detector<sheet::Rules> d; int crashes = 0;
        for (int i = 0; i < 600; ++i) crashes += d.update(i * dt, 90, 0.1, 0.0, false).kind == Detection::crash;
        CHECK(crashes == 0);
    }
    {   // hard braking 90 -> 30 with no damage: nothing
        shadow::Detector<sheet::Rules> d; int crashes = 0;
        for (int i = 0; i < 180; ++i) crashes += d.update(i * dt, 90 - i * (60.0 / 180), 0.6, 0.0, false).kind == Detection::crash;
        CHECK(crashes == 0);
    }
    {   // crash: 90 km/h -> 15 km/h in 0.1 s with a wear jump, then a second bump inside the cooldown
        shadow::Detector<sheet::Rules> d; int crashes = 0; Detection hit;
        double t = 0;
        for (int i = 0; i < 120; ++i, t += dt) d.update(t, 90, 0.1, 0.10, false);
        for (int i = 0; i < 6; ++i, t += dt) {
            Detection r = d.update(t, 90 - (i + 1) * 12.5, 4.0, 0.10 + 0.01 * (i + 1), false);
            if (r.kind == Detection::crash) { ++crashes; hit = r; }
        }
        for (int i = 0; i < 60; ++i, t += dt) {   // bump again 1 s later: cooldown
            Detection r = d.update(t, 10, 2.0, 0.2 + 0.001 * i, false);
            crashes += r.kind == Detection::crash;
        }
        CHECK(crashes == 1);
        CHECK(hit.impact_kmh >= 89 && hit.impact_kmh <= 91);
        CHECK(hit.peak_g >= 3.9);
        CHECK(hit.trigger == "physics");
    }
    {   // fine-only crash (ATS fined a crash, physics below thresholds)
        shadow::Detector<sheet::Rules> d; Detection r;
        for (int i = 0; i < 30; ++i) d.update(i * dt, 40, 0.1, 0.0, false);
        r = d.update(30 * dt, 40, 0.1, 0.0, true);
        CHECK(r.kind == Detection::crash && r.trigger == "fine");
    }
    {   // repair: wear drops from 0.3 to 0.0
        shadow::Detector<sheet::Rules> d; int repairs = 0;
        for (int i = 0; i < 30; ++i) d.update(i * dt, 0, 0, 0.3, false);
        for (int i = 30; i < 60; ++i) repairs += d.update(i * dt, 0, 0, 0.0, false).kind == Detection::repair;
        CHECK(repairs == 1);
    }

    std::cerr << (failures ? "plugin tests FAILED\n" : "plugin tests passed\n");
    return failures ? 1 : 0;
}
