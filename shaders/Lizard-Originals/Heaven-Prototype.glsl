// GSIM shader collection for use with Ghostty 1.3.x+.
// Deep Crimson Heaven (天) - Prototype
// 
//
// Constructed via Oriented Box SDFs for hard edges.
// Deep Red Pulsing Core + Dark Red Glow
//

#define SCALE            0.28
#define PULSE_SPEED      2.5
#define KANJI_Y_OFFSET   0.05

const vec3 FIRE_CORE = vec3(0.70, 0.05, 0.05); 
const vec3 FIRE_GLOW = vec3(0.40, 0.00, 0.00); 

// Box for SDF 
float sdOrientedBox(in vec2 p, in vec2 a, in vec2 b, float th)
{
    float l = length(b - a);
    vec2  d = (b - a) / l;
    vec2  q = p - (a + b) * 0.5;
    q = mat2(d.x, -d.y, d.y, d.x) * q;
    q = abs(q) - vec2(l * 0.5, th);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// Kanji SDF: 天 (Heaven) 
float kanjiTenSDF(vec2 p) 
{
    p /= SCALE;
    p.y += KANJI_Y_OFFSET;

    float d = 100.0;
    float stroke = 0.045; // Thickness of brush strokes

    // Top horizontal line
    d = min(d, sdOrientedBox(p, vec2(-0.35, 0.35), vec2(0.35, 0.35), stroke));

    // Bottom horizontal line
    d = min(d, sdOrientedBox(p, vec2(-0.55, 0.1), vec2(0.55, 0.1), stroke));

    // Left sweeping leg 
    d = min(d, sdOrientedBox(p, vec2(0.0, 0.35), vec2(-0.1, 0.1), stroke));
    d = min(d, sdOrientedBox(p, vec2(-0.1, 0.1), vec2(-0.5, -0.5), stroke));

    // Right sweeping leg
    d = min(d, sdOrientedBox(p, vec2(-0.1, 0.1), vec2(0.5, -0.5), stroke));

    return d * SCALE;
}

// Dynamic Bloom
float bloom(float d, float spread) 
{
    return exp(-spread * abs(d));
}

// Core Fill
float shapeFill(float d) 
{
    return smoothstep(0.01, -0.01, d);
}

//------------------------------------------------------------
void mainImage(out vec4 fragColor, in vec2 fragCoord) 
{
    if(iResolution.y == 0.0)
        return;

    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;

    // Read the terminal screen behind the shader
    vec4 tex = texture(iChannel0, uv);
    vec3 col = tex.rgb;
    float alpha = tex.a; 

    // Create a mask so the Kanji only appears over dark backgrounds
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    float darkMask = 1.0 - smoothstep(0.05, 0.20, lum);

    //--------------------------------------------------------
    vec2 p = uv - 0.5;
    p.x *= aspect;

    // Time-based pulsing math (0.0 to 1.0 smooth sine wave)
    float pulse = sin(iTime * PULSE_SPEED) * 0.5 + 0.5;

    // Calculate distance field
    float d = kanjiTenSDF(p);

    // Make the glow spread expand and contract
    float glowSpread = mix(35.0, 18.0, pulse); 
    float glow = bloom(d, glowSpread);
    
    // Core remains solid with hard boundaries
    float fill = shapeFill(d);

    // Modulate the color intensity based on the pulse
    vec3 currentGlow = mix(FIRE_GLOW * 0.05, FIRE_GLOW * 0.3, pulse);

    //--------------------------------------------------------
    
    // Additive blend for the glowing halo
    col += currentGlow * glow * darkMask;
    
    // Hard edge for the core
    col += FIRE_CORE * fill * darkMask;

    // Preserve terminal transparency, adding opacity where the kanji exists
    float addedAlpha = (glow * 0.5 + fill) * darkMask;
    alpha = clamp(alpha + addedAlpha, 0.0, 1.0);

    //--------------------------------------------------------
    fragColor = vec4(col, alpha);
}
