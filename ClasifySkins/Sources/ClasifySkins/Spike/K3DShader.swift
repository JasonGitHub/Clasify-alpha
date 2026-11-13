/// SPIKE (CLA-101): the mock's WebGL shaders in Metal Shading Language, compiled at run time
/// with `makeLibrary(source:)`. The math is the frozen `k3d_src.js` (K.3D.1, `vr = 1`) line by
/// line. Two changes:
/// - `ss` replaces `smoothstep`, because the mock calls it with edge0 > edge1, which Metal
///   does not define. `ss` is the GLSL formula.
/// - The front's material id (its alpha) is read with nearest filtering, and its color with
///   linear filtering. The mock reads both linear, so ids blend at the center button's edge
///   and show as dark specks: a known flaw that is not ported.
/// - No normal flip for back faces: the mock culls them, so its flip never runs. The renderer
///   draws with no culling and lets the depth test hide the inside.
enum K3DShader {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct K3DUniforms { float4x4 mv; float4x4 pr; float vr; };

    struct K3DVarying {
        float4 position [[position]];
        float3 vn; float3 vp; float2 vuv; float2 vuv2; float vm; float vwt;
    };

    vertex K3DVarying k3dVertex(uint id [[vertex_id]], const device float* data [[buffer(0)]],
                                constant K3DUniforms& u [[buffer(1)]]) {
        const device float* e = data + id * 12;
        float4 q = u.mv * float4(e[0], e[1], e[2], 1.0);
        float3x3 m3 = float3x3(u.mv[0].xyz, u.mv[1].xyz, u.mv[2].xyz);
        K3DVarying o;
        o.vp = q.xyz;
        o.vn = m3 * float3(e[3], e[4], e[5]);
        o.vuv = float2(e[6], e[7]);
        o.vuv2 = float2(e[8], e[9]);
        o.vwt = e[10];
        o.vm = e[11];
        o.position = u.pr * q;
        return o;
    }

    float ss(float e0, float e1, float x) { float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }
    float box(float3 r, float3 d, float w) { return ss(1.0 - w, 1.0 - w * 0.35, dot(r, normalize(d))); }
    float seg(float z, float z0, float z1, float a, float b) { return mix(a, b, ss(z0, z1, z)); }

    // Studio bands by how far the reflection turns away from the viewer.
    float env(float3 r) {
        float z = r.z, L = 0.40;
        L = seg(z, -1.0, -0.9, 0.40, 0.92);
        if (z > -0.9) L = seg(z, -0.9, -0.6, 0.92, 0.40);
        if (z > -0.6) L = seg(z, -0.6, -0.3, 0.40, 0.28);
        if (z > -0.3) L = seg(z, -0.3, 0.0, 0.28, 0.58);
        if (z > 0.0) L = seg(z, 0.0, 0.35, 0.58, 0.98);
        if (z > 0.35) L = seg(z, 0.35, 0.65, 0.98, 0.82);
        if (z > 0.65) L = seg(z, 0.65, 1.0, 0.82, 0.88);
        L += 0.06 * r.y + 0.10 * box(r, float3(-0.4, 0.5, 0.75), 0.3);
        return clamp(L, 0.05, 1.0);
    }

    float rbox(float2 q, float2 c, float2 h, float rr, float e) {
        float2 d = abs(q - c) - h + rr;
        float k = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - rr;
        return ss(e, -e, k);
    }

    // K.3D.1: the room the mirror reflects, fixed to the camera, with a little parallax.
    float studio(float3 r, float3 p) {
        float2 q = r.xy + p.xy / 1400.0;
        float L = 0.15 + 0.10 * ss(-0.2, 1.0, q.y) + 0.03 * sin(q.x * 3.1 + q.y * 1.7);
        float hz = -0.17 + 0.04 * q.x;
        L = mix(L, 0.09, ss(0.0, 0.03, q.y - hz) * ss(0.16, 0.03, q.y - hz));
        float fl = ss(0.012, -0.012, q.y - hz);
        L = mix(L, 0.50 + 0.30 * ss(hz - 0.7, hz - 0.05, q.y), fl);
        L = mix(L, 1.0, rbox(q, float2(-0.42, 0.40), float2(0.20, 0.14), 0.05, 0.015));
        L = mix(L, 0.80, rbox(q, float2(0.78, 0.15), float2(0.08, 0.55), 0.04, 0.06));
        return clamp(L, 0.04, 1.0);
    }

    fragment float4 k3dFragment(K3DVarying in [[stage_in]], constant K3DUniforms& u [[buffer(0)]],
                                texture2d<float> tf [[texture(0)]], texture2d<float> tb [[texture(1)]],
                                texture2d<float> ts [[texture(2)]], sampler sm [[sampler(0)]],
                                sampler sn [[sampler(1)]]) {
        float3x3 m3 = float3x3(u.mv[0].xyz, u.mv[1].xyz, u.mv[2].xyz);
        float3 n = normalize(in.vn);
        float3 v = normalize(-in.vp);
        float3 r = reflect(-v, n);
        float3 Ld = normalize(float3(-0.45, 0.55, 0.7));
        float dif = max(dot(n, Ld), 0.0);
        float vm = in.vm;
        float3 col;
        if (vm < 0.5) {  // anodized aluminium
            float3 alb = float3(0.80, 0.81, 0.82);
            col = alb * (0.74 + 0.30 * dif) + 0.08 * env(r);
            col *= mix(0.62, 1.0, pow(max(dot(n, v), 0.0), 0.5));
        } else if (vm < 1.5) {  // mirror steel
            float3 s = mix(ts.sample(sm, in.vuv2).rgb, ts.sample(sm, in.vuv).rgb, in.vwt);
            if (u.vr > 0.5) {
                s = 0.22 + 0.78 * s;
                col = mix(s * (0.80 + 0.26 * env(r)), float3(studio(r, in.vp)), 0.62) + 0.18 * pow(max(0.0, 1.0 - abs(dot(n, v))), 6.0);
            } else {
                col = s * (0.78 + 0.30 * env(r));
            }
        } else if (vm < 2.5) {  // seam
            col = float3(0.16);
        } else if (vm < 3.5) {  // front
            float4 t4 = tf.sample(sm, in.vuv);
            float3 t = t4.rgb;
            float id = tf.sample(sn, in.vuv).a;  // the material id, not blended
            if (u.vr > 0.5) {
                float body = step(abs(id - 253.0 / 255.0), 0.0018);
                float btn = step(abs(id - 249.0 / 255.0), 0.0018);
                if (btn > 0.5) {  // center button: a shallow dish, its normal leans to the center
                    float2 d = (in.vuv - float2(365.5 / 732.0, 865.0 / 1226.0)) * float2(366.0, -613.0) / 40.75;
                    float3 tx = normalize(m3 * float3(1.0, 0.0, 0.0)), ty = normalize(m3 * float3(0.0, 1.0, 0.0));
                    n = normalize(n - 0.10 * (d.x * tx + d.y * ty));
                    r = reflect(-v, n);
                    dif = max(dot(n, Ld), 0.0);
                    body = 1.0;
                }
                float2 q = r.xy + in.vp.xy / 900.0;
                float fe = 0.62 + 0.20 * ss(-0.7, 0.7, q.y)
                    + 0.18 * ss(0.35, 0.97, dot(r, normalize(float3(-0.45, 0.5, 0.75))))
                    + 0.06 * ss(0.5, 0.95, dot(r, normalize(float3(0.6, 0.2, 0.75))));
                float3 alu = float3(0.985, 0.985, 0.99) * fe * (t / 0.773) * (0.93 + 0.07 * dif);
                alu += (t.r / 0.773 - 1.0) * 0.8 * ss(0.75, 1.0, fe);  // sparkle in the light
                alu = mix(alu, min(alu, float3(0.95)), btn);  // the dish never blows out to white
                float gz = 1.0 - max(dot(n, v), 0.0);
                alu += float3(0.42 * pow(gz, 1.6)) * (1.0 - btn);  // the rolled edge glows at grazing
                float3 wh = t * (0.74 + 0.20 * dif) + 0.04 * env(r);  // wheel: off-white, matte
                col = mix(mix(t * (0.80 + 0.24 * dif) + 0.05 * env(r), wh, step(0.998, id)), alu, body);
                // LCD: dim, cool, darker and flatter at an angle.
                float lcd = step(abs(id - 251.0 / 255.0), 0.0018);
                float win = max(lcd, step(abs(id - 250.0 / 255.0), 0.0018));
                float3 lc = (0.10 + 0.74 * col) * float3(0.95, 0.98, 1.04);
                float va = ss(0.03, 0.30, gz);
                lc = mix(lc, float3(0.07, 0.075, 0.085) + 0.22 * lc, va);
                col = mix(col, lc, lcd);
                // The clear window reflects the room as a plane with a hard edge.
                float2 qs = r.xy + in.vp.xy / 520.0;
                float wall = ss(-0.012, 0.012, qs.x * 0.85 + qs.y * 0.55 - 0.10);
                float rl = mix(0.22, 0.95, wall) * min(0.05 + 2.6 * gz, 0.9);
                col = col + win * float3(rl) * (1.0 - col * 0.6);
            } else {
                col = t * (0.80 + 0.24 * dif) + 0.05 * env(r);
            }
        } else {  // back: steel and etching
            float e = env(r);
            float4 t = tb.sample(sm, in.vuv);
            if (u.vr > 0.5) {
                float3 s = 0.22 + 0.78 * ts.sample(sm, in.vuv).rgb;
                float m = studio(r, in.vp);
                float3 st = mix(s * (0.82 + 0.2 * e), float3(m) * float3(0.985, 0.99, 1.0), 0.92);
                float lum = dot(t.rgb, float3(0.3, 0.59, 0.11));
                float sat = max(t.r, max(t.g, t.b)) - min(t.r, min(t.g, t.b));
                float tone = mix(0.80, 0.30 + 0.52 * ss(0.12, 0.45, lum), ss(0.06, 0.2, sat) * (1.0 - step(2.2, t.r / max(t.g, 0.05))));
                float sl = dot(st, float3(0.33));
                tone = mix(tone, 0.30 + 0.55 * (tone - 0.30), ss(0.35, 0.75, sl));
                float3 frost = float3(tone * (0.90 + 0.12 * dif));  // frosted laser etch
                col = mix(st, frost, t.a);
            } else {
                float3 st = ts.sample(sm, in.vuv).rgb * (0.80 + 0.24 * e);
                col = mix(st, t.rgb, t.a);
            }
        }
        return float4(col, 1.0);
    }
    """
}
