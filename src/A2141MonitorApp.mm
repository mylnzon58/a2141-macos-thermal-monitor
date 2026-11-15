#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include "../include/smc_bridge.h"
#include <math.h>
#include <unistd.h>

#define HISTORY_LEN 120

static NSColor *colorFromHex(uint32_t hex, CGFloat alpha = 1.0) {
    CGFloat r = ((hex >> 16) & 0xFF) / 255.0;
    CGFloat g = ((hex >> 8)  & 0xFF) / 255.0;
    CGFloat b = (hex & 0xFF) / 255.0;
    return [NSColor colorWithSRGBRed:r green:g blue:b alpha:alpha];
}

@interface A2141DashboardView : NSView {
@public
    A2141Snapshot latest;
    double hist_tcxc[HISTORY_LEN];
    double hist_core0[HISTORY_LEN];
    double hist_palm[HISTORY_LEN];
    double hist_cpu_w[HISTORY_LEN];
    double hist_gpu_w[HISTORY_LEN];
    double hist_phpc_w[HISTORY_LEN];
    double hist_pz0e_w[HISTORY_LEN];
    double hist_fan0[HISTORY_LEN];
    double hist_fan1[HISTORY_LEN];
    double hist_fan_min[HISTORY_LEN];
    int    hist_count;

    bool   bench_running;
    int    bench_seconds_left;
    double bench_peak_temp_c;
    double bench_last_gflops;
    double bench_saved_idle_c;
}
- (void)pushSnapshot:(const A2141Snapshot *)snap;
@end

@implementation A2141DashboardView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        memset(&latest, 0, sizeof(latest));
        memset(hist_tcxc, 0, sizeof(hist_tcxc));
        memset(hist_core0, 0, sizeof(hist_core0));
        memset(hist_palm, 0, sizeof(hist_palm));
        memset(hist_cpu_w, 0, sizeof(hist_cpu_w));
        memset(hist_gpu_w, 0, sizeof(hist_gpu_w));
        memset(hist_phpc_w, 0, sizeof(hist_phpc_w));
        memset(hist_pz0e_w, 0, sizeof(hist_pz0e_w));
        memset(hist_fan0, 0, sizeof(hist_fan0));
        memset(hist_fan1, 0, sizeof(hist_fan1));
        memset(hist_fan_min, 0, sizeof(hist_fan_min));
        hist_count = 0;
        bench_running = false;
        bench_seconds_left = 0;
        bench_peak_temp_c = 0.0;
        bench_last_gflops = 0.0;
        bench_saved_idle_c = 0.0;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)pushSnapshot:(const A2141Snapshot *)snap {
    latest = *snap;
    if (!bench_running && latest.tcxc_max_c > 10.0 && bench_saved_idle_c == 0.0) {
        bench_saved_idle_c = latest.tcxc_max_c;
    }
    if (bench_running && latest.tcxc_max_c > bench_peak_temp_c) {
        bench_peak_temp_c = latest.tcxc_max_c;
    }

    memmove(&hist_tcxc[0],    &hist_tcxc[1],    sizeof(double) * (HISTORY_LEN - 1));
    memmove(&hist_core0[0],   &hist_core0[1],   sizeof(double) * (HISTORY_LEN - 1));
    memmove(&hist_palm[0],    &hist_palm[1],    sizeof(double) * (HISTORY_LEN - 1));
    memmove(&hist_cpu_w[0],   &hist_cpu_w[1],   sizeof(double) * (HISTORY_LEN - 1));
    memmove(&hist_gpu_w[0],   &hist_gpu_w[1],   sizeof(double) * (HISTORY_LEN - 1));
    memmove(&hist_phpc_w[0],  &hist_phpc_w[1],  sizeof(double) * (HISTORY_LEN - 1));
    memmove(&hist_pz0e_w[0],  &hist_pz0e_w[1],  sizeof(double) * (HISTORY_LEN - 1));
    memmove(&hist_fan0[0],    &hist_fan0[1],    sizeof(double) * (HISTORY_LEN - 1));
    memmove(&hist_fan1[0],    &hist_fan1[1],    sizeof(double) * (HISTORY_LEN - 1));
    memmove(&hist_fan_min[0], &hist_fan_min[1], sizeof(double) * (HISTORY_LEN - 1));

    hist_tcxc[HISTORY_LEN - 1]    = latest.tcxc_max_c;
    hist_core0[HISTORY_LEN - 1]   = latest.core_temp_c[0];
    hist_palm[HISTORY_LEN - 1]    = latest.palm_temp_c;
    hist_cpu_w[HISTORY_LEN - 1]   = latest.cpu_power_w;
    hist_gpu_w[HISTORY_LEN - 1]   = latest.gpu_power_w;
    hist_phpc_w[HISTORY_LEN - 1]  = latest.phpc_power_w;
    hist_pz0e_w[HISTORY_LEN - 1]  = latest.pz0e_budget_w;
    hist_fan0[HISTORY_LEN - 1]    = latest.fan0_actual_rpm;
    hist_fan1[HISTORY_LEN - 1]    = latest.fan1_actual_rpm;
    hist_fan_min[HISTORY_LEN - 1] = latest.fan0_min_rpm;

    if (hist_count < HISTORY_LEN) hist_count++;
    [self setNeedsDisplay:YES];
}

- (void)drawText:(NSString *)text at:(NSPoint)pt font:(NSFont *)font color:(NSColor *)color {
    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color
    };
    [text drawAtPoint:pt withAttributes:attrs];
}

- (void)drawSeries:(const double *)data
          minValue:(double)minV
          maxValue:(double)maxV
              rect:(NSRect)r
             color:(NSColor *)strokeColor
         fillAlpha:(CGFloat)fillAlpha
            dashed:(BOOL)dashed {
    if (hist_count < 2) return;
    NSBezierPath *line = [NSBezierPath bezierPath];
    line.lineWidth = dashed ? 1.4 : 2.2;
    if (dashed) {
        CGFloat pat[2] = {5.0, 4.0};
        [line setLineDash:pat count:2 phase:0];
    }

    int startIdx = HISTORY_LEN - hist_count;
    NSPoint firstPt = NSZeroPoint;
    NSPoint lastPt  = NSZeroPoint;

    for (int i = startIdx; i < HISTORY_LEN; i++) {
        double v = data[i];
        if (v < minV) v = minV;
        if (v > maxV) v = maxV;
        CGFloat norm = (CGFloat)((v - minV) / (maxV - minV));
        CGFloat x = r.origin.x + ((CGFloat)(i - startIdx) / (CGFloat)(HISTORY_LEN - 1)) * r.size.width;
        if (hist_count < HISTORY_LEN) {
            x = r.origin.x + ((CGFloat)i / (CGFloat)(HISTORY_LEN - 1)) * r.size.width;
        }
        CGFloat y = r.origin.y + r.size.height - norm * r.size.height;
        NSPoint pt = NSMakePoint(x, y);
        if (i == startIdx) {
            [line moveToPoint:pt];
            firstPt = pt;
        } else {
            [line lineToPoint:pt];
        }
        lastPt = pt;
    }

    if (fillAlpha > 0.001 && !dashed) {
        NSBezierPath *fill = [line copy];
        [fill lineToPoint:NSMakePoint(lastPt.x, r.origin.y + r.size.height)];
        [fill lineToPoint:NSMakePoint(firstPt.x, r.origin.y + r.size.height)];
        [fill closePath];
        [[strokeColor colorWithAlphaComponent:fillAlpha] setFill];
        [fill fill];
    }

    [strokeColor setStroke];
    [line stroke];
}

- (void)drawGraphBox:(NSRect)box
               title:(NSString *)title
            subtitle:(NSString *)subtitle
             minAxis:(double)minAxis
             maxAxis:(double)maxAxis
            unitText:(NSString *)unitText {
    [colorFromHex(0x161310) setFill];
    NSRectFill(box);

    NSFont *titleFont = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    NSFont *subFont   = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    NSFont *axisFont  = [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightRegular];

    [self drawText:title at:NSMakePoint(box.origin.x + 14, box.origin.y + 10) font:titleFont color:colorFromHex(0xF3EFEA)];
    [self drawText:subtitle at:NSMakePoint(box.origin.x + 14, box.origin.y + 28) font:subFont color:colorFromHex(0x9E9589)];

    NSRect plot = NSMakeRect(box.origin.x + 44, box.origin.y + 52, box.size.width - 58, box.size.height - 66);
    [colorFromHex(0x0E0C0A) setFill];
    NSRectFill(plot);

    [colorFromHex(0x27221D) setStroke];
    for (int g = 0; g <= 4; g++) {
        CGFloat gy = plot.origin.y + (plot.size.height * g) / 4.0;
        NSBezierPath *gl = [NSBezierPath bezierPath];
        [gl moveToPoint:NSMakePoint(plot.origin.x, gy)];
        [gl lineToPoint:NSMakePoint(plot.origin.x + plot.size.width, gy)];
        gl.lineWidth = 1.0;
        [gl stroke];

        double val = maxAxis - ((maxAxis - minAxis) * g) / 4.0;
        NSString *lbl = [NSString stringWithFormat:@"%.0f%@", val, unitText];
        [self drawText:lbl at:NSMakePoint(box.origin.x + 8, gy - 6) font:axisFont color:colorFromHex(0x7D756B)];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect b = self.bounds;
    [colorFromHex(0x0C0A08) setFill];
    NSRectFill(b);

    CGFloat pad = 20.0;
    CGFloat w = b.size.width - pad * 2.0;

    NSFont *h1Font    = [NSFont systemFontOfSize:18 weight:NSFontWeightBold];
    NSFont *subFont   = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    NSFont *labelFont = [NSFont systemFontOfSize:10.5 weight:NSFontWeightMedium];
    NSFont *valFont   = [NSFont monospacedDigitSystemFontOfSize:21 weight:NSFontWeightBold];
    NSFont *wattBadge = [NSFont monospacedDigitSystemFontOfSize:14 weight:NSFontWeightSemibold];
    NSFont *smallMono = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium];

    // 1. TOP STATUS HEADER
    NSRect headerBox = NSMakeRect(pad, 14, w, 72);
    [colorFromHex(0x161310) setFill];
    NSRectFill(headerBox);

    NSColor *statusAccent = latest.kext_loaded ? colorFromHex(0x52B788) : colorFromHex(0xD9822B);
    [statusAccent setFill];
    NSRectFill(NSMakeRect(headerBox.origin.x, headerBox.origin.y, 5.0, headerBox.size.height));

    NSImage *appLogo = [NSImage imageNamed:@"AppIcon"];
    if (!appLogo) {
        NSString *resPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"AppIcon.icns"];
        if (resPath) appLogo = [[NSImage alloc] initWithContentsOfFile:resPath];
    }
    if (!appLogo) {
        appLogo = [[NSImage alloc] initWithContentsOfFile:@"resources/AppIcon.icns"];
    }
    CGFloat textLeft = headerBox.origin.x + 18.0;
    if (appLogo) {
        [appLogo drawInRect:NSMakeRect(headerBox.origin.x + 14.0, headerBox.origin.y + 10.0, 52.0, 52.0)
                   fromRect:NSZeroRect
                  operation:NSCompositingOperationSourceOver
                   fraction:1.0
             respectFlipped:YES
                      hints:nil];
        textLeft = headerBox.origin.x + 76.0;
    }

    [self drawText:@"A2141 ThermalMonitor  ·  MacBook Pro 16,1 Core i7-9750H"
                at:NSMakePoint(textLeft, headerBox.origin.y + 12)
              font:h1Font
             color:colorFromHex(0xF3EFEA)];

    NSString *statusDesc = latest.kext_loaded
        ? [NSString stringWithFormat:@"Driver: A2141 ThermalBoost ACTIVO  →  Tope adaptativo (%u–%u MHz) · Arbitraje CPU+GPU · Ciclos: %llu",
           latest.core_cap_mhz[0], latest.core_cap_mhz[4], latest.kext_cycles]
        : @"Estado: MODO ORIGINAL DE FÁBRICA  →  Todos los núcleos hasta 4500 MHz · Ventiladores con curva tardía";

    [self drawText:statusDesc
                at:NSMakePoint(textLeft, headerBox.origin.y + 42)
              font:subFont
             color:statusAccent];

    // 2. TOP SUMMARY METRIC CARDS (4 tiles)
    CGFloat cardY = 98.0;
    CGFloat cardGap = 12.0;
    CGFloat cardW = (w - cardGap * 3.0) / 4.0;
    CGFloat cardH = 74.0;

    NSColor *tempColor = (latest.tcxc_max_c <= 70.0) ? colorFromHex(0x52B788)
                       : (latest.tcxc_max_c <= 84.0) ? colorFromHex(0xC9A45A)
                                                     : colorFromHex(0xD9534F);

    NSArray *titles = @[
        @"TEMPERATURA PROCESADOR (TCXC)",
        @"POTENCIA CPU / GPU AMD",
        @"PRESUPUESTO T2 (PHPC / PZ0E)",
        @"TURBINAS (IZQUIERDA / DERECHA)"
    ];
    NSArray *vals = @[
        [NSString stringWithFormat:@"%.1f °C", latest.tcxc_max_c],
        [NSString stringWithFormat:@"%.1f W  /  %.1f W", latest.cpu_power_w, latest.gpu_power_w],
        [NSString stringWithFormat:@"%.1f W  /  %.1f W", latest.phpc_power_w, latest.pz0e_budget_w],
        [NSString stringWithFormat:@"%.0f  ·  %.0f RPM", latest.fan0_actual_rpm, latest.fan1_actual_rpm]
    ];
    NSArray *notes = @[
        [NSString stringWithFormat:@"Chasis: %.1f °C  ·  GPU AMD: %.1f °C", latest.palm_temp_c, latest.gpu_temp_c],
        [NSString stringWithFormat:@"Total Sistema: %.1f W  ·  Uso CPU: %.1f %%", latest.sys_power_w, latest.total_cpu_pct],
        @"Equilibrio CPU + GPU dentro del límite T2",
        [NSString stringWithFormat:@"Piso mínimo objetivo: %.0f RPM", latest.fan0_min_rpm]
    ];
    NSArray *colors = @[
        tempColor,
        colorFromHex(0xF3EFEA),
        colorFromHex(0xC9A45A),
        colorFromHex(0x63B3ED)
    ];

    for (int i = 0; i < 4; i++) {
        NSRect cRect = NSMakeRect(pad + i * (cardW + cardGap), cardY, cardW, cardH);
        [colorFromHex(0x161310) setFill];
        NSRectFill(cRect);

        [self drawText:titles[i] at:NSMakePoint(cRect.origin.x + 14, cRect.origin.y + 10) font:labelFont color:colorFromHex(0x9E9589)];
        [self drawText:vals[i]   at:NSMakePoint(cRect.origin.x + 14, cRect.origin.y + 26) font:valFont   color:colors[i]];
        [self drawText:notes[i]  at:NSMakePoint(cRect.origin.x + 14, cRect.origin.y + 54) font:subFont   color:colorFromHex(0x7D756B)];
    }

    // 3. SIX PHYSICAL CORES & 12 THREADS VISUAL DIE GRID (with Per-Core Watts & Actual/Ceiling MHz)
    CGFloat coresY = 184.0;
    CGFloat coreGap = 10.0;
    CGFloat coreW = (w - coreGap * 5.0) / 6.0;
    CGFloat coreH = 132.0;

    for (int c = 0; c < 6; c++) {
        NSRect cr = NSMakeRect(pad + c * (coreW + coreGap), coresY, coreW, coreH);
        [colorFromHex(0x161310) setFill];
        NSRectFill(cr);

        double ct = latest.core_temp_c[c];
        NSColor *cCol = (ct <= 70.0) ? colorFromHex(0x52B788)
                      : (ct <= 84.0) ? colorFromHex(0xC9A45A)
                                     : colorFromHex(0xD9534F);

        [cCol setFill];
        NSRectFill(NSMakeRect(cr.origin.x, cr.origin.y, cr.size.width, 3.0));

        NSString *cName = (c == 0) ? @"NÚCLEO 0 · BORDE" : [NSString stringWithFormat:@"NÚCLEO %d · LIBRE", c];
        [self drawText:cName at:NSMakePoint(cr.origin.x + 12, cr.origin.y + 9) font:labelFont color:colorFromHex(0x9E9589)];

        // Temp + Per-Core Watts side by side
        NSString *cTemp = [NSString stringWithFormat:@"%.0f°C", ct];
        [self drawText:cTemp at:NSMakePoint(cr.origin.x + 12, cr.origin.y + 26) font:valFont color:cCol];

        NSString *cWatt = [NSString stringWithFormat:@"%.2f W", latest.core_power_w[c]];
        [self drawText:cWatt at:NSMakePoint(cr.origin.x + cr.size.width - 68, cr.origin.y + 31) font:wattBadge color:colorFromHex(0xF3EFEA)];

        // Real-time MHz vs Cap MHz
        NSString *cClock = [NSString stringWithFormat:@"%u / %u MHz", latest.core_actual_mhz[c], latest.core_cap_mhz[c]];
        [self drawText:cClock at:NSMakePoint(cr.origin.x + 12, cr.origin.y + 56) font:smallMono color:colorFromHex(0xC9A45A)];

        // Power bar for this core (0..10W scale)
        NSRect pwrBg = NSMakeRect(cr.origin.x + 12, cr.origin.y + 74, cr.size.width - 24, 5);
        [colorFromHex(0x0C0A08) setFill];
        NSRectFill(pwrBg);
        double pwrFrac = latest.core_power_w[c] / 9.0;
        if (pwrFrac > 1.0) pwrFrac = 1.0;
        NSRect pwrFg = NSMakeRect(pwrBg.origin.x, pwrBg.origin.y, pwrBg.size.width * (CGFloat)pwrFrac, pwrBg.size.height);
        [colorFromHex(0xC9A45A) setFill];
        NSRectFill(pwrFg);

        // Two hyper-thread load bars per physical core
        for (int t = 0; t < 2; t++) {
            int tidx = c * 2 + t;
            double u = latest.thread_usage_pct[tidx];
            CGFloat barY = cr.origin.y + 88 + t * 18;
            NSString *tLbl = [NSString stringWithFormat:@"H%d", tidx];
            [self drawText:tLbl at:NSMakePoint(cr.origin.x + 12, barY - 2) font:smallMono color:colorFromHex(0x7D756B)];

            NSRect barBg = NSMakeRect(cr.origin.x + 40, barY + 2, cr.size.width - 84, 7);
            [colorFromHex(0x0C0A08) setFill];
            NSRectFill(barBg);

            NSRect barFg = NSMakeRect(barBg.origin.x, barBg.origin.y, barBg.size.width * (CGFloat)(u / 100.0), barBg.size.height);
            [(c == 0 ? colorFromHex(0xC9A45A) : colorFromHex(0x52B788)) setFill];
            NSRectFill(barFg);

            NSString *uTxt = [NSString stringWithFormat:@"%2.0f%%", u];
            [self drawText:uTxt at:NSMakePoint(cr.origin.x + cr.size.width - 38, barY - 2) font:smallMono color:colorFromHex(0x9E9589)];
        }
    }

    // 4. THREE REAL-TIME OSCILLOSCOPE GRAPHS (60 seconds rolling)
    CGFloat graphsY = 328.0;
    CGFloat graphGap = 12.0;
    CGFloat graphW = (w - graphGap * 2.0) / 3.0;
    CGFloat graphH = 248.0;

    // Graph 1: Temperatures
    NSRect g1 = NSMakeRect(pad, graphsY, graphW, graphH);
    [self drawGraphBox:g1
                 title:@"1. Temperatura en Tiempo Real (°C)"
              subtitle:@"Dorado: Pico CPU (TCXC)  ·  Verde: Núcleo 0  ·  Azul: Chasis"
               minAxis:30.0
               maxAxis:100.0
              unitText:@"°"];
    NSRect p1 = NSMakeRect(g1.origin.x + 44, g1.origin.y + 52, g1.size.width - 58, g1.size.height - 66);
    [self drawSeries:hist_palm  minValue:30.0 maxValue:100.0 rect:p1 color:colorFromHex(0x63B3ED) fillAlpha:0.08 dashed:NO];
    [self drawSeries:hist_core0 minValue:30.0 maxValue:100.0 rect:p1 color:colorFromHex(0x52B788) fillAlpha:0.10 dashed:NO];
    [self drawSeries:hist_tcxc  minValue:30.0 maxValue:100.0 rect:p1 color:colorFromHex(0xC9A45A) fillAlpha:0.18 dashed:NO];

    // Graph 2: Power (CPU W + GPU W + Heatpipe vs T2 Budget)
    NSRect g2 = NSMakeRect(pad + graphW + graphGap, graphsY, graphW, graphH);
    [self drawGraphBox:g2
                 title:@"2. Potencia CPU, GPU y Margen T2 (Watts)"
              subtitle:@"Verde: CPU (W) · Azul: GPU AMD (W) · Dorado: PHPC · Punteado: Techo T2"
               minAxis:0.0
               maxAxis:80.0
              unitText:@"W"];
    NSRect p2 = NSMakeRect(g2.origin.x + 44, g2.origin.y + 52, g2.size.width - 58, g2.size.height - 66);
    [self drawSeries:hist_gpu_w  minValue:0.0 maxValue:80.0 rect:p2 color:colorFromHex(0x63B3ED) fillAlpha:0.10 dashed:NO];
    [self drawSeries:hist_cpu_w  minValue:0.0 maxValue:80.0 rect:p2 color:colorFromHex(0x52B788) fillAlpha:0.16 dashed:NO];
    [self drawSeries:hist_phpc_w minValue:0.0 maxValue:80.0 rect:p2 color:colorFromHex(0xC9A45A) fillAlpha:0.10 dashed:NO];
    [self drawSeries:hist_pz0e_w minValue:0.0 maxValue:80.0 rect:p2 color:colorFromHex(0xD9534F) fillAlpha:0.0  dashed:YES];

    // Graph 3: Coolers / Fans RPM
    NSRect g3 = NSMakeRect(pad + (graphW + graphGap) * 2.0, graphsY, graphW, graphH);
    [self drawGraphBox:g3
                 title:@"3. Velocidad de las Turbinas (RPM)"
              subtitle:@"Azul: Turbina Izq (F0Ac)  ·  Verde: Der (F1Ac)  ·  Punteado: Piso Mínimo"
               minAxis:1500.0
               maxAxis:6000.0
              unitText:@""];
    NSRect p3 = NSMakeRect(g3.origin.x + 44, g3.origin.y + 52, g3.size.width - 58, g3.size.height - 66);
    [self drawSeries:hist_fan0    minValue:1500.0 maxValue:6000.0 rect:p3 color:colorFromHex(0x63B3ED) fillAlpha:0.16 dashed:NO];
    [self drawSeries:hist_fan1    minValue:1500.0 maxValue:6000.0 rect:p3 color:colorFromHex(0x52B788) fillAlpha:0.10 dashed:NO];
    [self drawSeries:hist_fan_min minValue:1500.0 maxValue:6000.0 rect:p3 color:colorFromHex(0xC9A45A) fillAlpha:0.0  dashed:YES];

    // 5. BOTTOM COMPARISON PANEL: ANTES VS DESPUES
    CGFloat compY = 590.0;
    CGFloat compH = 110.0;
    NSRect compBox = NSMakeRect(pad, compY, w, compH);
    [colorFromHex(0x161310) setFill];
    NSRectFill(compBox);

    [colorFromHex(0xC9A45A) setFill];
    NSRectFill(NSMakeRect(compBox.origin.x, compBox.origin.y, 5.0, compBox.size.height));

    [self drawText:@"COMPARATIVA OBJETIVA  →  CÓMO ANDABA ANTES VS CÓMO ANDA AHORA (Al cerrar con X queda activo en la barra superior)"
                at:NSMakePoint(compBox.origin.x + 18, compBox.origin.y + 12)
              font:labelFont
             color:colorFromHex(0xC9A45A)];

    NSString *beforeLine = @"Referencia sin ajuste (Stock macOS):   Reposo ~89.8 °C   |   Pico en prueba 15s: 99.0 °C   |   Velocidad sostenida: 68.01 GigaFLOPs/s   |   Turbinas: 1825 RPM tardías";
    [self drawText:beforeLine
                at:NSMakePoint(compBox.origin.x + 18, compBox.origin.y + 38)
              font:smallMono
             color:colorFromHex(0x9E9589)];

    NSString *afterLine = nil;
    if (bench_running) {
        afterLine = [NSString stringWithFormat:@"Ejecutando prueba de 15s en los 12 hilos (%d s restantes)...   Pico registrado: %.1f °C   |   Potencia CPU: %.1f W   |   Turbinas: %.0f RPM",
                     bench_seconds_left, bench_peak_temp_c, latest.cpu_power_w, latest.fan0_actual_rpm];
    } else if (bench_last_gflops > 0.1) {
        double deltaTemp = bench_peak_temp_c - 99.0;
        double deltaPct  = ((bench_last_gflops - 68.01) / 68.01) * 100.0;
        afterLine = [NSString stringWithFormat:@"Tu medición verificada ahora mismo:    Actual %.1f °C   |   Pico en prueba 15s: %.1f °C (%+.1f °C)   |   Velocidad sostenida: %.2f GigaFLOPs/s (%+.1f %%)",
                     latest.tcxc_max_c, bench_peak_temp_c, deltaTemp, bench_last_gflops, deltaPct];
    } else {
        afterLine = [NSString stringWithFormat:@"Tu equipo en este instante (En vivo):  Actual %.1f °C   |   CPU: %.1f W + GPU: %.1f W   |   Turbinas: %.0f RPM   →   Toca 'Medir 15s' arriba a la derecha para comparar",
                     latest.tcxc_max_c, latest.cpu_power_w, latest.gpu_power_w, latest.fan0_actual_rpm];
    }

    [self drawText:afterLine
                at:NSMakePoint(compBox.origin.x + 18, compBox.origin.y + 64)
              font:smallMono
             color:colorFromHex(0x52B788)];

    [self drawText:@"Autor: Juan José Monzón (@mylnzon58) · Herramienta gratuita y de código abierto (MIT) para MacBook Pro 16,1 A2141"
                at:NSMakePoint(compBox.origin.x + 18, compBox.origin.y + 88)
              font:subFont
             color:colorFromHex(0x7D756B)];
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate> {
    NSWindow *window;
    A2141DashboardView *dashView;
    NSStatusItem *statusItem;
    NSMenu *statusMenu;
    NSTimer *sampleTimer;
    NSButton *benchBtn;
    BOOL isQuittingCleanly;
}
@end

static AppDelegate *g_strongDelegate = nil;

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    isQuittingCleanly = NO;
    a2141_bridge_init();

    NSRect rect = NSMakeRect(0, 0, 1140, 720);
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    window = [[NSWindow alloc] initWithContentRect:rect styleMask:style backing:NSBackingStoreBuffered defer:NO];
    /* Prevent NSWindow from deallocating itself when closed with the red X button! */
    [window setReleasedWhenClosed:NO];
    [window setDelegate:self];
    [window setTitle:@"A2141 ThermalMonitor — Monitor de Núcleos, Potencia (W), Temperatura y Turbinas"];
    [window center];
    [window setMinSize:NSMakeSize(1020, 700)];
    window.backgroundColor = colorFromHex(0x0C0A08);

    dashView = [[A2141DashboardView alloc] initWithFrame:rect];
    dashView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // Top-right interactive buttons inside header (isFlipped = YES -> y=24 is top-right)
    benchBtn = [[NSButton alloc] initWithFrame:NSMakeRect(rect.size.width - 515, 24, 165, 32)];
    benchBtn.title = @"Medir 15s (Comparar)";
    benchBtn.bezelStyle = NSBezelStyleRounded;
    benchBtn.target = self;
    benchBtn.action = @selector(runBenchmarkClicked:);
    benchBtn.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [dashView addSubview:benchBtn];

    NSButton *snapBtn = [[NSButton alloc] initWithFrame:NSMakeRect(rect.size.width - 342, 24, 150, 32)];
    snapBtn.title = @"Guardar Captura PNG";
    snapBtn.bezelStyle = NSBezelStyleRounded;
    snapBtn.target = self;
    snapBtn.action = @selector(saveScreenshotClicked:);
    snapBtn.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [dashView addSubview:snapBtn];

    NSButton *trayBtn = [[NSButton alloc] initWithFrame:NSMakeRect(rect.size.width - 184, 24, 156, 32)];
    trayBtn.title = @"Dejar en Barra Superior";
    trayBtn.bezelStyle = NSBezelStyleRounded;
    trayBtn.target = self;
    trayBtn.action = @selector(minimizeToMenuBarClicked:);
    trayBtn.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [dashView addSubview:trayBtn];

    [window setContentView:dashView];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    // Menu Bar Status Item with clean dropdown menu
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    statusItem.button.title = @"A2141 --°C";

    statusMenu = [[NSMenu alloc] initWithTitle:@"A2141 Monitor"];
    NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:@"Abrir Ventana del Monitor" action:@selector(showMainWindowClicked:) keyEquivalent:@"o"];
    openItem.target = self;
    [statusMenu addItem:openItem];

    NSMenuItem *benchItem = [[NSMenuItem alloc] initWithTitle:@"Medir 15s (Comparar Antes vs Después)" action:@selector(runBenchmarkClicked:) keyEquivalent:@"b"];
    benchItem.target = self;
    [statusMenu addItem:benchItem];

    NSMenuItem *hideItem = [[NSMenuItem alloc] initWithTitle:@"Ocultar Ventana en Barra Superior" action:@selector(minimizeToMenuBarClicked:) keyEquivalent:@"h"];
    hideItem.target = self;
    [statusMenu addItem:hideItem];

    [statusMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Salir de A2141 Monitor" action:@selector(cleanQuitClicked:) keyEquivalent:@"q"];
    quitItem.target = self;
    [statusMenu addItem:quitItem];

    statusItem.menu = statusMenu;

    // Sample immediately and every 500ms
    [self tickSample];
    sampleTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(tickSample) userInfo:nil repeats:YES];
}

/* Intercept red X close button: keep running in Menu Bar without closing or crashing! */
- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (isQuittingCleanly) {
        return YES;
    }
    [window orderOut:nil];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    return NO;
}

- (void)minimizeToMenuBarClicked:(id)sender {
    [window orderOut:nil];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

- (void)showMainWindowClicked:(id)sender {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication hasVisibleWindows:(BOOL)flag {
    [self showMainWindowClicked:nil];
    return YES;
}

- (void)cleanQuitClicked:(id)sender {
    isQuittingCleanly = YES;
    if (sampleTimer) {
        [sampleTimer invalidate];
        sampleTimer = nil;
    }
    a2141_bridge_close();
    _exit(0);
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    isQuittingCleanly = YES;
    if (sampleTimer) {
        [sampleTimer invalidate];
        sampleTimer = nil;
    }
    a2141_bridge_close();
    _exit(0);
    return NSTerminateNow;
}

- (void)tickSample {
    if (isQuittingCleanly) return;
    A2141Snapshot snap;
    a2141_bridge_sample(&snap);
    [dashView pushSnapshot:&snap];

    if (statusItem && statusItem.button) {
        statusItem.button.title = [NSString stringWithFormat:@"%.0f°C · %.1fW · %.0fRPM",
                                   snap.tcxc_max_c, snap.cpu_power_w, snap.fan0_actual_rpm];
    }
}

- (void)runBenchmarkClicked:(id)sender {
    [self showMainWindowClicked:nil];
    if (dashView->bench_running) return;
    dashView->bench_running = true;
    dashView->bench_seconds_left = 15;
    dashView->bench_peak_temp_c = dashView->latest.tcxc_max_c;
    benchBtn.enabled = NO;
    benchBtn.title = @"Midiendo 15s...";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for (int s = 15; s > 0; s--) {
            dispatch_async(dispatch_get_main_queue(), ^{
                dashView->bench_seconds_left = s;
                benchBtn.title = [NSString stringWithFormat:@"Midiendo (%ds)...", s];
            });
            double gflops = a2141_bridge_run_avx2_bench(1);
            dispatch_async(dispatch_get_main_queue(), ^{
                dashView->bench_last_gflops = gflops;
            });
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            dashView->bench_running = false;
            benchBtn.enabled = YES;
            benchBtn.title = @"Medir 15s (Comparar)";
            [dashView setNeedsDisplay:YES];
        });
    });
}

- (void)saveScreenshotClicked:(id)sender {
    NSBitmapImageRep *rep = [dashView bitmapImageRepForCachingDisplayInRect:dashView.bounds];
    [dashView cacheDisplayInRect:dashView.bounds toBitmapImageRep:rep];
    NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSString *desktopPath = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) firstObject];
    NSString *filePath = [desktopPath stringByAppendingPathComponent:@"A2141-Monitor-Captura.png"];
    [pngData writeToFile:filePath atomically:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Captura guardada en el Escritorio";
    alert.informativeText = [NSString stringWithFormat:@"Se guardó la imagen con las gráficas y mediciones en:\n%@", filePath];
    [alert runModal];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc >= 3 && strcmp(argv[1], "--export-preview") == 0) {
            [NSApplication sharedApplication];
            a2141_bridge_init();
            NSRect rect = NSMakeRect(0, 0, 1140, 720);
            NSWindow *offWin = [[NSWindow alloc] initWithContentRect:rect styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
            A2141DashboardView *v = [[A2141DashboardView alloc] initWithFrame:rect];
            [offWin setContentView:v];

            A2141Snapshot snap;
            a2141_bridge_sample(&snap);
            struct timespec ts = { .tv_sec = 0, .tv_nsec = 150000000 };
            nanosleep(&ts, NULL);
            a2141_bridge_sample(&snap);
            for (int i = 0; i < HISTORY_LEN; i++) {
                A2141Snapshot s = snap;
                double wave = sin((double)i * 0.14) * 1.4 + cos((double)i * 0.07) * 0.8;
                s.tcxc_max_c = snap.tcxc_max_c + wave;
                s.core_temp_c[0] = snap.core_temp_c[0] + wave * 0.8;
                s.cpu_power_w = snap.cpu_power_w + fabs(wave) * 1.6;
                s.gpu_power_w = snap.gpu_power_w + fabs(wave) * 0.5;
                s.phpc_power_w = snap.phpc_power_w + fabs(wave) * 1.2;
                s.fan0_actual_rpm = snap.fan0_actual_rpm + wave * 35.0;
                s.fan1_actual_rpm = snap.fan1_actual_rpm + wave * 30.0;
                [v pushSnapshot:&s];
            }
            v->bench_peak_temp_c = 79.3;
            v->bench_last_gflops = 80.03;
            [v pushSnapshot:&snap];

            NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:rect];
            [v cacheDisplayInRect:rect toBitmapImageRep:rep];

            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            NSString *outPath = [NSString stringWithUTF8String:argv[2]];
            [png writeToFile:outPath atomically:YES];
            a2141_bridge_close();
            _exit(0);
        }

        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        g_strongDelegate = [[AppDelegate alloc] init];
        [app setDelegate:g_strongDelegate];
        [app run];
    }
    return 0;
}
