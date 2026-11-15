#ifndef SMC_BRIDGE_H
#define SMC_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double tcxc_max_c;          // PECI Max Die Temp (C)
    double core_temp_c[6];      // Physical Cores 0..5 Temp (C)
    double gpu_temp_c;          // Radeon Pro GPU Temp (TG0P / TG0D)
    double palm_temp_c;         // Skin / Palm Rest Temp (Ts0S)
    double cpu_power_w;         // CPU Package Power (PC0R)
    double sys_power_w;         // Total System Power (PSTR)
    double phpc_power_w;        // High Power Heatpipe Load (PHPC)
    double pz0e_budget_w;       // T2 Dynamic CPU+GPU Budget (PZ0E)
    double fan0_actual_rpm;     // Left Fan Actual RPM (F0Ac)
    double fan1_actual_rpm;     // Right Fan Actual RPM (F1Ac)
    double fan0_min_rpm;        // Left Fan Min Floor RPM (F0Mn)
    double fan1_min_rpm;        // Right Fan Min Floor RPM (F1Mn)
    double core_usage_pct[6];   // Physical Core 0..5 Usage (0..100%)
    double thread_usage_pct[12];// Logical Thread 0..11 Usage (0..100%)
    double total_cpu_pct;       // Average CPU Usage (0..100%)
    bool   kext_loaded;         // A2141AsymmetricHWP loaded in IORegistry
    uint32_t kext_profile;      // 0=AUTO, 1=BURST, 2=HEAVY
    uint64_t kext_cycles;       // Ring-0 IPI cycles executed
    uint32_t core_cap_mhz[6];   // Active HWP ceiling per core (MHz)
} A2141Snapshot;

int  a2141_bridge_init(void);
void a2141_bridge_close(void);
void a2141_bridge_sample(A2141Snapshot *out);
double a2141_bridge_run_avx2_bench(int seconds);

#ifdef __cplusplus
}
#endif

#endif
