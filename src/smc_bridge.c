#include "../include/smc_bridge.h"
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <mach/mach_host.h>
#include <pthread.h>
#include <immintrin.h>
#include <sys/sysctl.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <math.h>

typedef struct {
    uint32_t version;
    uint32_t active_profile;
    uint32_t enabled;
    uint32_t pl1_watts;
    uint32_t pl2_watts;
    uint32_t tcc_offset;
    uint32_t pkg_temp_c;
    uint32_t avg_perf_ratio;
    uint32_t core_temp_c[6];
    uint32_t core_applied_ratio[6];
    uint32_t core_guard_events[6];
    uint64_t enforce_cycles;
    uint64_t rapl_Override_count;
    uint64_t last_pkg_power_msr;
} A2141KextTelemetry;

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_READ_KEYINFO 9

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    uint16_t release;
} SMCKeyData_vers_t;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef unsigned char SMCBytes_t[32];

typedef struct {
    uint32_t key;
    SMCKeyData_vers_t vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t keyInfo;
    char result;
    char status;
    char data8;
    uint32_t data32;
    SMCBytes_t bytes;
} SMCKeyData_t;

static io_connect_t g_smc_conn = 0;
static processor_cpu_load_info_t g_prev_cpu_load = NULL;
static mach_msg_type_number_t g_prev_cpu_MsgCount = 0;
static natural_t g_prev_proc_count = 0;

static uint32_t str_to_fourcc(const char *s) {
    return ((uint32_t)(unsigned char)s[0] << 24) |
           ((uint32_t)(unsigned char)s[1] << 16) |
           ((uint32_t)(unsigned char)s[2] << 8)  |
           ((uint32_t)(unsigned char)s[3]);
}

int a2141_bridge_init(void) {
    if (g_smc_conn != 0) return 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &g_smc_conn);
    IOObjectRelease(svc);
    return (kr == KERN_SUCCESS) ? 0 : -1;
}

void a2141_bridge_close(void) {
    if (g_smc_conn) {
        IOServiceClose(g_smc_conn);
        g_smc_conn = 0;
    }
    if (g_prev_cpu_load) {
        vm_deallocate(mach_task_self(), (vm_address_t)g_prev_cpu_load, g_prev_cpu_MsgCount * sizeof(int));
        g_prev_cpu_load = NULL;
    }
}

static double smc_read_float(const char *key) {
    if (!g_smc_conn && a2141_bridge_init() != 0) return 0.0;

    SMCKeyData_t inData;
    SMCKeyData_t outData;
    size_t outSize = sizeof(SMCKeyData_t);

    memset(&inData, 0, sizeof(inData));
    memset(&outData, 0, sizeof(outData));
    inData.key = str_to_fourcc(key);
    inData.data8 = SMC_CMD_READ_KEYINFO;

    kern_return_t kr = IOConnectCallStructMethod(g_smc_conn, KERNEL_INDEX_SMC, &inData, sizeof(inData), &outData, &outSize);
    if (kr != KERN_SUCCESS) return 0.0;

    uint32_t dataType = outData.keyInfo.dataType;
    uint32_t dataSize = outData.keyInfo.dataSize;

    inData.keyInfo.dataSize = dataSize;
    inData.data8 = SMC_CMD_READ_BYTES;
    outSize = sizeof(SMCKeyData_t);
    kr = IOConnectCallStructMethod(g_smc_conn, KERNEL_INDEX_SMC, &inData, sizeof(inData), &outData, &outSize);
    if (kr != KERN_SUCCESS) return 0.0;

    uint32_t t_flt  = str_to_fourcc("flt ");
    uint32_t t_sp78 = str_to_fourcc("sp78");
    uint32_t t_fpe2 = str_to_fourcc("fpe2");

    if (dataType == t_flt && dataSize == 4) {
        float v = 0.0f;
        memcpy(&v, outData.bytes, 4);
        return (double)v;
    } else if (dataType == t_sp78 && dataSize == 2) {
        int16_t raw = (int16_t)(((uint16_t)outData.bytes[0] << 8) | (uint16_t)outData.bytes[1]);
        return (double)raw / 256.0;
    } else if (dataType == t_fpe2 && dataSize == 2) {
        uint16_t raw = ((uint16_t)outData.bytes[0] << 8) | (uint16_t)outData.bytes[1];
        return (double)raw / 4.0;
    }
    return 0.0;
}

static void sample_cpu_load(A2141Snapshot *out) {
    natural_t proc_count = 0;
    processor_cpu_load_info_t cpu_load = NULL;
    mach_msg_type_number_t msg_count = 0;

    kern_return_t kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &proc_count, (processor_info_array_t *)&cpu_load, &msg_count);
    if (kr != KERN_SUCCESS || !cpu_load) return;

    double sum_total = 0.0;
    natural_t max_threads = (proc_count < 12) ? proc_count : 12;

    if (g_prev_cpu_load && g_prev_proc_count == proc_count) {
        for (natural_t i = 0; i < max_threads; i++) {
            uint64_t user   = cpu_load[i].cpu_ticks[CPU_STATE_USER]   - g_prev_cpu_load[i].cpu_ticks[CPU_STATE_USER];
            uint64_t sys    = cpu_load[i].cpu_ticks[CPU_STATE_SYSTEM] - g_prev_cpu_load[i].cpu_ticks[CPU_STATE_SYSTEM];
            uint64_t nice   = cpu_load[i].cpu_ticks[CPU_STATE_NICE]   - g_prev_cpu_load[i].cpu_ticks[CPU_STATE_NICE];
            uint64_t idle   = cpu_load[i].cpu_ticks[CPU_STATE_IDLE]   - g_prev_cpu_load[i].cpu_ticks[CPU_STATE_IDLE];
            uint64_t busy   = user + sys + nice;
            uint64_t total  = busy + idle;
            double pct = (total > 0) ? ((double)busy * 100.0 / (double)total) : 0.0;
            if (pct > 100.0) pct = 100.0;
            out->thread_usage_pct[i] = pct;
            sum_total += pct;
        }
        for (int c = 0; c < 6; c++) {
            double t0 = out->thread_usage_pct[c * 2];
            double t1 = out->thread_usage_pct[c * 2 + 1];
            out->core_usage_pct[c] = (t0 + t1) * 0.5;
        }
        out->total_cpu_pct = (max_threads > 0) ? (sum_total / (double)max_threads) : 0.0;
    }

    if (g_prev_cpu_load) {
        vm_deallocate(mach_task_self(), (vm_address_t)g_prev_cpu_load, g_prev_cpu_MsgCount * sizeof(int));
    }
    g_prev_cpu_load = cpu_load;
    g_prev_cpu_MsgCount = msg_count;
    g_prev_proc_count = proc_count;
}

static void sample_kext_and_core_power(A2141Snapshot *out) {
    out->kext_loaded = false;
    out->kext_profile = 0;
    out->kext_cycles = 0;

    uint32_t actual_ratios[6] = {0, 0, 0, 0, 0, 0};
    size_t rlen = sizeof(actual_ratios);
    bool has_actual = (sysctlbyname("machdep.a2141_core_actual_ratio", actual_ratios, &rlen, NULL, 0) == 0);

    A2141KextTelemetry kt;
    size_t len = sizeof(kt);
    memset(&kt, 0, sizeof(kt));
    if (sysctlbyname("machdep.a2141_telemetry", &kt, &len, NULL, 0) == 0 && kt.enabled != 0) {
        out->kext_loaded  = true;
        out->kext_profile = kt.active_profile;
        out->kext_cycles  = kt.enforce_cycles;
        for (int i = 0; i < 6; i++) {
            out->core_cap_mhz[i] = kt.core_applied_ratio[i] * 100U;
            if (kt.core_temp_c[i] > 10 && kt.core_temp_c[i] < 115) {
                out->core_temp_c[i] = (double)kt.core_temp_c[i];
            }
            if (has_actual && actual_ratios[i] >= 8 && actual_ratios[i] <= 46) {
                out->core_actual_mhz[i] = actual_ratios[i] * 100U;
            } else {
                double u = out->core_usage_pct[i] / 100.0;
                uint32_t est = (uint32_t)(1200.0 + u * (double)(out->core_cap_mhz[i] - 1200));
                if (est > out->core_cap_mhz[i]) est = out->core_cap_mhz[i];
                out->core_actual_mhz[i] = est;
            }
        }
    } else {
        uint32_t stock_mhz[6] = {4500, 4500, 4500, 4500, 4500, 4500};
        for (int i = 0; i < 6; i++) {
            out->core_cap_mhz[i] = stock_mhz[i];
            double u = out->core_usage_pct[i] / 100.0;
            out->core_actual_mhz[i] = (uint32_t)(2600.0 + u * 1900.0);
        }
    }

    /* Distribute CPU package/core power across the 6 physical cores based on
     * physical CMOS dynamic + leakage power weights:
     *   W_i = (f_i / 2.6 GHz)^2 * (0.18 + 0.82 * usage_i) + 0.12 * exp(0.022 * (T_i - 50))
     * Normalized so sum(core_power_w[0..5]) == total CPU power (PC0R).
     */
    double total_cpu_w = (out->cpu_power_w > 0.5) ? out->cpu_power_w : 6.0;
    double weights[6];
    double weight_sum = 0.0;
    for (int i = 0; i < 6; i++) {
        double f_ghz = (double)out->core_actual_mhz[i] / 1000.0;
        double u_frac = out->core_usage_pct[i] / 100.0;
        double t_c = (out->core_temp_c[i] > 25.0) ? out->core_temp_c[i] : 60.0;
        double dyn_w = (f_ghz / 2.6) * (f_ghz / 2.6) * (0.18 + 0.82 * u_frac);
        double leak_w = 0.12 * exp(0.022 * (t_c - 50.0));
        weights[i] = dyn_w + leak_w;
        weight_sum += weights[i];
    }
    if (weight_sum <= 0.0001) weight_sum = 1.0;
    for (int i = 0; i < 6; i++) {
        out->core_power_w[i] = total_cpu_w * (weights[i] / weight_sum);
    }
}

void a2141_bridge_sample(A2141Snapshot *out) {
    if (!out) return;
    memset(out, 0, sizeof(*out));

    out->tcxc_max_c = smc_read_float("TCXC");
    const char *ckeys[6] = {"TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C"};
    for (int i = 0; i < 6; i++) {
        out->core_temp_c[i] = smc_read_float(ckeys[i]);
        if (out->core_temp_c[i] <= 1.0) out->core_temp_c[i] = out->tcxc_max_c - (double)(i % 3);
    }
    if (out->tcxc_max_c <= 1.0) out->tcxc_max_c = out->core_temp_c[0];

    out->gpu_temp_c      = smc_read_float("TGDD");
    if (out->gpu_temp_c <= 1.0) out->gpu_temp_c = smc_read_float("TG0P");
    out->palm_temp_c     = smc_read_float("Ts0S");
    out->cpu_power_w     = smc_read_float("PC0R");
    out->cpu_core_rail_w = smc_read_float("PC0C");
    out->gpu_power_w     = smc_read_float("PG0R");
    out->sys_power_w     = smc_read_float("PSTR");
    out->phpc_power_w    = smc_read_float("PHPC");
    out->pz0e_budget_w   = smc_read_float("PZ0E");
    out->fan0_actual_rpm = smc_read_float("F0Ac");
    out->fan1_actual_rpm = smc_read_float("F1Ac");
    out->fan0_min_rpm    = smc_read_float("F0Mn");
    out->fan1_min_rpm    = smc_read_float("F1Mn");

    sample_cpu_load(out);
    sample_kext_and_core_power(out);
}

typedef struct {
    volatile int *running;
    uint64_t flops;
} BenchWorker;

static void *avx2_worker_fn(void *arg) {
    BenchWorker *w = (BenchWorker *)arg;
    __m256d a = _mm256_set1_pd(1.0000001);
    __m256d b = _mm256_set1_pd(0.9999999);
    __m256d c0 = _mm256_set1_pd(0.5);
    __m256d c1 = _mm256_set1_pd(0.4);
    __m256d c2 = _mm256_set1_pd(0.3);
    __m256d c3 = _mm256_set1_pd(0.2);
    uint64_t local_flops = 0;

    while (*(w->running)) {
        for (int i = 0; i < 25000; i++) {
            c0 = _mm256_fmadd_pd(a, c0, b);
            c1 = _mm256_fmadd_pd(a, c1, b);
            c2 = _mm256_fmadd_pd(a, c2, b);
            c3 = _mm256_fmadd_pd(a, c3, b);
        }
        local_flops += 25000ULL * 32ULL;
    }
    double sink = ((double *)&c0)[0] + ((double *)&c1)[0] + ((double *)&c2)[0] + ((double *)&c3)[0];
    if (sink == 123456.789) local_flops++;
    w->flops = local_flops;
    return NULL;
}

double a2141_bridge_run_avx2_bench(int seconds) {
    if (seconds < 1) seconds = 1;
    if (seconds > 30) seconds = 30;

    volatile int running = 1;
    pthread_t threads[12];
    BenchWorker workers[12];
    memset(workers, 0, sizeof(workers));

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    for (int i = 0; i < 12; i++) {
        workers[i].running = &running;
        pthread_create(&threads[i], NULL, avx2_worker_fn, &workers[i]);
    }

    struct timespec req = { .tv_sec = seconds, .tv_nsec = 0 };
    nanosleep(&req, NULL);
    running = 0;

    uint64_t total_flops = 0;
    for (int i = 0; i < 12; i++) {
        pthread_join(threads[i], NULL);
        total_flops += workers[i].flops;
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed = (double)(t1.tv_sec - t0.tv_sec) + (double)(t1.tv_nsec - t0.tv_nsec) / 1e9;
    if (elapsed <= 0.0) elapsed = (double)seconds;
    return ((double)total_flops / 1e9) / elapsed;
}
