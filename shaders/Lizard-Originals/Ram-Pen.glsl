// Reactive-Cursor.glsl
// GSIM shader collection for use with ghostty 1.3.0+.
// Optimized with Deterministic Space-Folding Smear, Ripples, Arc Architectures. 
// BSD-3-Clause-v2 (Modified - Name Attribution Required)  

//Copyright (c) 2026 GrandBIRDLizard.
//ALL rights reserved.

#define DURATION 0.5
#define DRAW_THRESHOLD 1.5
#define HIDE_TRAILS_ON_THE_SAME_LINE 0 // Use 1 to hide, 0 to show

// Toggle Switches (1/0 opposite for GLSL)
#define ENABLE_TRAIL 1
#define ENABLE_ELECTRIC 1
#define ENABLE_PULSE 1

// INTENSITY & GLOW CONTROLS (Toned down to prevent blinding cursor glow)
#define ARC_GLOW_INTENSITY 0.08   // Ambient halo around the electric arc (was 0.40)
#define ARC_CORE_INTENSITY 0.85   // Brightness of the crisp electric filament line
#define TRAIL_MAX_OPACITY  0.20   // Master opacity cap for the smear trail

// SMEAR ARCHITECTURE SETTINGS
// SMEAR_STYLE:
// 0 = Smooth Ramp (Continuous dynamic thickness)
// 1 = Block Ramp (Quantized distinct blocks)
// 2 = Pulse Blocks (Blocks scaling to a rhythmic wave)
// 3 = Pulse Circles (Circles scaling to a rhythmic wave)
#define SMEAR_STYLE 2

// SMEAR_REVERSE:
// 0 = Small -> Large (Tail is thin, Head is thick)
// 1 = Large -> Small (Tail is thick, Head is thin):
#define SMEAR_REVERSE 1

// Modifiers:
#define SMEAR_STEPS 30.0      // Amount of chunks for styles 1, 2, and 3
#define SMEAR_MIN_SIZE 1.5    // Trail starting scale
#define SMEAR_MAX_SIZE 3.5    // Trail ending scale
#define PULSE_COUNT 14.0       // Number of pulses active (Styles 2 & 3)
#define PULSE_SPEED 5.0      // Speed of the pulse wave (Styles 2 & 3)

// Pulse Settings (End-Animation)
#define PULSE_DURATION 0.8
#define PULSE_MAX_RADIUS 0.003
#define PULSE_THICKNESS 0.005

// PULSE_STYLE:
// 0 = Rectangular Ring (Matches active cursor profile bounds)
// 1 = Circular Ripple (Uniform mathematical radial expansion)
#define PULSE_STYLE 1

const vec4 TRAIL_COLOR_ACCENT = vec4(0.45, 0.20, 0.75, 1.0);

vec2 normalizeCoord(vec2 coord, float includeAspect) {
    vec2 result = coord / iResolution.xy;
    if (includeAspect > 0.5) {
        result.x *= iResolution.x / iResolution.y;
    }
    return result;
}
float blend(float t) {
    return pow(1.0 - t, 10.0);
}

float easeOutSine(float t) {
    return sin(t * 1.5707963);
}

vec2 getRectangleCenter(vec4 rect) {
    return rect.xy + vec2(rect.z * 0.5, -rect.w * 0.5);
}

float getSdfRectRing(vec2 p, vec2 center, vec2 halfSize, float thickness) {
    vec2 d = abs(p - center) - halfSize;
    float outsideSdf = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
    return abs(outsideSdf) - thickness * 0.5;
}

// Tesla Coil / Electric Arc Math
#if ENABLE_ELECTRIC == 1
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    value += amplitude * noise(p); p *= 2.0; amplitude *= 0.5;
    value += amplitude * noise(p); p *= 2.0; amplitude *= 0.5;
    value += amplitude * noise(p); p *= 2.0; amplitude *= 0.5;
    value += amplitude * noise(p); p *= 2.0; amplitude *= 0.5;
    return value;
}

float electricArc(vec2 p, vec2 a, vec2 b, float time, float progress) {
    vec2 dir = normalize(b - a);
    vec2 perp = vec2(-dir.y, dir.x);
    float dist = distance(a, b);
    
    float t = clamp(dot(p - a, dir) / max(dist, 0.0001), 0.0, 1.0);
    vec2 projected = a + dir * t * dist;
    vec2 offset = perp * (fbm(vec2(t * 10.0, time * 10.0)) - 0.5) * 0.08 * progress;
    
    float d = length(p - (projected + offset));
    
    float branchTime = time * 15.0;
    float branchFreq = 5.0;
    vec2 branchOffset = perp * (sin(t * branchFreq + branchTime) * 0.02 * progress);
    float branchDist = length(p - (projected + branchOffset));
    
    float branchMask = step(0.5, progress);
    d = mix(d, min(d, branchDist), branchMask);
    
    return d;
}
#endif

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    if (iResolution.y == 0.0) return;

    vec4 baseTex = texture(iChannel0, fragCoord / iResolution.xy);
    vec3 finalColor = baseTex.rgb;
    float originalAlpha = baseTex.a;

    vec2 vu = normalizeCoord(fragCoord, 1.0);

    vec4 currentCursor = vec4(
        normalizeCoord(iCurrentCursor.xy, 1.0),
        normalizeCoord(iCurrentCursor.zw, 0.0)
    );

    vec4 previousCursor = vec4(
        normalizeCoord(iPreviousCursor.xy, 1.0),
        normalizeCoord(iPreviousCursor.zw, 0.0)
    );

    vec2 centerCC = getRectangleCenter(currentCursor);
    vec2 centerPC = getRectangleCenter(previousCursor);

    float lineLength = distance(centerCC, centerPC);
    float trailThreshold = DRAW_THRESHOLD * currentCursor.w;
    float isFarEnough = step(trailThreshold, lineLength);
    
    #if HIDE_TRAILS_ON_THE_SAME_LINE == 1
        float isOnSeparateLine = step(0.0001, abs(currentCursor.y - previousCursor.y));
    #else
        float isOnSeparateLine = 1.0;
    #endif

    #if ENABLE_TRAIL == 1 || ENABLE_ELECTRIC == 1
        float trailProgress = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);
        float easedTrailProgress = blend(trailProgress);
        float safeLineLength = max(lineLength * easedTrailProgress, 0.00001);

        float trailActive = isFarEnough * isOnSeparateLine * step(0.001, easedTrailProgress);
        
        float distanceToEnd = distance(vu, centerCC);
        float alphaModifier = clamp(distanceToEnd / safeLineLength, 0.0, 1.0);
        float trailOpacity = (1.0 - alphaModifier) * trailActive;
    #endif

    // Dynamic Smear Trail
    #if ENABLE_TRAIL == 1
        vec2 pa = vu - centerPC;
        vec2 ba = centerCC - centerPC;
        float ba2 = dot(ba, ba) + 1e-6; 
        float h = clamp(dot(pa, ba) / ba2, 0.0, 1.0);

        #if SMEAR_REVERSE == 1
            float h_dir = 1.0 - h;
        #else
            float h_dir = h;
        #endif

        float sdfTrail;
        
        #if SMEAR_STYLE == 0
            float r = mix(SMEAR_MIN_SIZE, SMEAR_MAX_SIZE, h_dir);
            vec2 currentCenter = centerPC + ba * h;
            vec2 dynamicHalfBounds = vec2(currentCursor.z, currentCursor.w) * 0.5 * r;
            vec2 d_rect = abs(vu - currentCenter) - dynamicHalfBounds;
            sdfTrail = length(max(d_rect, 0.0)) + min(max(d_rect.x, d_rect.y), 0.0);

        #else
            float h_snapped = clamp(floor(h * SMEAR_STEPS + 0.5) / SMEAR_STEPS, 0.0, 1.0);
            
            #if SMEAR_REVERSE == 1
                float h_snapped_dir = 1.0 - h_snapped;
            #else
                float h_snapped_dir = h_snapped;
            #endif

            vec2 currentCenter = centerPC + ba * h_snapped;

            #if SMEAR_STYLE == 1
                float r = mix(SMEAR_MIN_SIZE, SMEAR_MAX_SIZE, h_snapped_dir);
                vec2 dynamicHalfBounds = vec2(currentCursor.z, currentCursor.w) * 0.5 * r;
                vec2 d_rect = abs(vu - currentCenter) - dynamicHalfBounds;
                sdfTrail = length(max(d_rect, 0.0)) + min(max(d_rect.x, d_rect.y), 0.0);

            #elif SMEAR_STYLE == 2
                float pulse = sin(h_snapped * 3.14159 * PULSE_COUNT - iTime * PULSE_SPEED) * 0.5 + 0.5;
                float r = mix(SMEAR_MIN_SIZE, SMEAR_MAX_SIZE, h_snapped_dir) * pulse;
                vec2 dynamicHalfBounds = vec2(currentCursor.z, currentCursor.w) * 0.5 * r;
                vec2 d_rect = abs(vu - currentCenter) - dynamicHalfBounds;
                sdfTrail = length(max(d_rect, 0.0)) + min(max(d_rect.x, d_rect.y), 0.0);

            #elif SMEAR_STYLE == 3
                float pulse = sin(h_snapped * 3.14159 * PULSE_COUNT - iTime * PULSE_SPEED) * 0.5 + 0.5;
                float r = mix(SMEAR_MIN_SIZE, SMEAR_MAX_SIZE, h_snapped_dir) * pulse;
                float baseRadius = max(currentCursor.z, currentCursor.w) * 0.5;
                sdfTrail = length(vu - currentCenter) - (baseRadius * r * 1.5);
            #endif
        #endif

        float trailMask = 1.0 - smoothstep(-0.01, 0.001, sdfTrail);
        float trailIntensity = trailOpacity * trailMask * TRAIL_MAX_OPACITY;

        finalColor = mix(finalColor, iCursorColor.rgb, trailIntensity * 0.35);
        finalColor = mix(finalColor, TRAIL_COLOR_ACCENT.rgb, trailIntensity);
    #endif

    // Electric Arc Overlay
    #if ENABLE_ELECTRIC == 1
        // Tightened arc core thickness for crisp rendering
        float arcThickness = 0.0025 + 0.0015 * sin(iTime * 25.0);
        float arcDist = electricArc(vu, centerCC, centerPC, iTime, easedTrailProgress);
        
        // Tighter inner core and reduced outer glow halo
        float arcAlpha = (1.0 - smoothstep(arcThickness * 0.4, arcThickness, arcDist)) * trailOpacity;
        float glowAlpha = (1.0 - smoothstep(arcThickness, arcThickness * 2.5, arcDist)) * trailOpacity;
        
        vec3 pulseArcColor = mix(iCursorColor.rgb, TRAIL_COLOR_ACCENT.rgb, 0.5 + 0.5 * sin(iTime * 20.0));
        
        // Apply crisp electric core line
        finalColor = mix(finalColor, pulseArcColor, arcAlpha * ARC_CORE_INTENSITY);
        // Apply muted ambient glow so it doesn't wash out the terminal cursor text
        finalColor = mix(finalColor, iCursorColor.rgb * 0.3, glowAlpha * ARC_GLOW_INTENSITY);
    #endif

    // Pulse (End-Animation)
    #if ENABLE_PULSE == 1
        float pulseProgress = clamp((iTime - iTimeCursorChange) / PULSE_DURATION, 0.0, 1.0);
        float pulseActive = isFarEnough * isOnSeparateLine * step(pulseProgress, 0.999);
        float pulseFade = 1.0 - pulseProgress;
        float expansionFactor = easeOutSine(pulseProgress) * PULSE_MAX_RADIUS;

        float sdfPulse;

        #if PULSE_STYLE == 0
            vec2 currentHalfBounds = vec2(currentCursor.z, currentCursor.w) * 0.5;

            float isBar = step(currentCursor.z / currentCursor.w, 0.25);
            float isUnderline = step(currentCursor.w / currentCursor.z, 0.25);
         
            vec2 expansionDirection = vec2(1.0, 1.0);
            expansionDirection = mix(expansionDirection, vec2(1.0, 0.2), isUnderline);
            expansionDirection = mix(expansionDirection, vec2(0.2, 1.0), isBar);

            vec2 animatedHalfBounds = currentHalfBounds + (vec2(expansionFactor) * expansionDirection);
            sdfPulse = getSdfRectRing(vu, centerCC, animatedHalfBounds, PULSE_THICKNESS);
        #else
            float baseRadius = max(currentCursor.z, currentCursor.w) * 0.5;
            float animatedRadius = baseRadius + expansionFactor;
            sdfPulse = abs(length(vu - centerCC) - animatedRadius) - PULSE_THICKNESS * 0.5;
        #endif

        float pulseMask = 1.0 - smoothstep(-0.01, 0.001, sdfPulse);
        float pulseIntensity = pulseMask * pulseFade * pulseActive;

        finalColor = mix(finalColor, TRAIL_COLOR_ACCENT.rgb, pulseIntensity * 0.80);
    #endif

    fragColor = vec4(finalColor, originalAlpha);
}
