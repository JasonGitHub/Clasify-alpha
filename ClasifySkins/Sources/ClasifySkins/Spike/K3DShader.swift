/// SPIKE (CLA-101): the K.3D.7 shaders in Metal Shading Language, compiled at run time with
/// `makeLibrary(source:)`. The math is the frozen `k3d_src3.js` (`data-edge="parts"`, the
/// physical light, `uPhys` 1) for the assembled device, line by line, with its uniforms fixed
/// at the frozen values (`UC` in the mock). Not ported, as the folder's README says: the old
/// light (`uPhys` 0), the 2D layer (`u2d`, `t2`), the other edge options, and everything only
/// Take apart draws (`ex` > 0, materials above 10, back faces). The LCD parallax (`lcdUV`) is
/// part of the frozen look and is ported (the README's correction, 23:20 JST 11-13).
///
/// Changes from the mock:
/// - `ss` replaces `smoothstep`, because the mock calls it with edge0 > edge1, which Metal does
///   not define. `ss` is the GLSL formula.
/// - One front texture with mipmaps. The color is read with the mipmapped linear sampler, like
///   the mock's `tm`. The material id (alpha) is read from level 0 with nearest filtering, like
///   the mock's `tf`.
/// - Back faces are culled as in the mock, so the mock's normal flip for them never runs.
enum K3DShader {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct K3DUniforms { float4x4 mv; float4x4 pr; float blk; };

    struct K3DVarying {
        float4 position [[position]];
        float3 vn; float3 vp; float3 vo; float2 vuv; float2 vuv2; float vm; float vwt; float vpt;
    };

    vertex K3DVarying k3dVertex(uint id [[vertex_id]], const device float* data [[buffer(0)]],
                                constant K3DUniforms& u [[buffer(1)]]) {
        const device float* e = data + id * 13;
        float4 q = u.mv * float4(e[0], e[1], e[2], 1.0);
        float3x3 m3 = float3x3(u.mv[0].xyz, u.mv[1].xyz, u.mv[2].xyz);
        K3DVarying o;
        o.vo = float3(e[0], e[1], e[2]);
        o.vp = q.xyz;
        o.vn = m3 * float3(e[3], e[4], e[5]);
        o.vuv = float2(e[6], e[7]);
        o.vuv2 = float2(e[8], e[9]);
        o.vwt = e[10];
        o.vm = e[11];
        o.vpt = e[12];
        o.position = u.pr * q;
        return o;
    }

    // The frozen light (UC): a lamp fixed in the room, 350 pt left, 800 pt up and 1000 pt out from
    // the front face (z = 34), and the room as a bright ceiling and a darker floor.
    constant float3 lamp = float3(-350.0, 800.0, 34.0 + 1000.0 - 2600.0);
    constant float uKey = 1.08, uCeil = 0.5, uFloor = 0.2, uGs = 0.75, uGa = 0.035, uVa = 0.35;
    constant float3 uTint = float3(0.995, 0.997, 1.0);
    constant float2 wheelUV = float2(366.0 / 732.0, 867.0 / 1226.0);

    float ss(float e0, float e1, float x) { float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }
    float box(float3 r, float3 d, float w) { return ss(1.0 - w, 1.0 - w * 0.35, dot(r, normalize(d))); }
    float seg(float z, float z0, float z1, float a, float b) { return mix(a, b, ss(z0, z1, z)); }
    float isId(float a, float id) { return step(abs(a - id / 255.0), 0.0018); }

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

    // The room the mirror steel reflects, fixed to the camera, with a little parallax.
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

    // The physical light, linear: the lamp (Lambert, inverse square, 1 at the device's center)
    // plus the room by the normal's height.
    float physE(float3 n, float3 vp, float3 vo, float3x3 M) {
        float3 ctr = vp - M * vo;
        float3 dl = lamp - vp;
        float d2 = dot(dl, dl), dC = length(lamp - ctr);
        return uKey * max(dot(n, dl) / sqrt(d2), 0.0) * dC * dC / d2 + mix(uFloor, uCeil, 0.5 + 0.5 * n.y);
    }

    // Matte metal in the physical light: the tint, 58% reflective, back to sRGB.
    float3 matte(float E) { return pow(pow(uTint, float3(2.2)) * 0.58 * E, float3(0.4545)); }

    // The LCD sits 4 pt under the clear window: at an angle its picture shifts against the bezel.
    float2 lcdUV(float3 n, float3 vp, float3x3 M, float2 uv) {
        float3 v = normalize(-vp);
        float3 tx = normalize(M * float3(1.0, 0.0, 0.0)), ty = normalize(M * float3(0.0, 1.0, 0.0));
        float vz = max(dot(v, n), 0.2);
        float2 off = float2(dot(v, tx), dot(v, ty)) / vz * 4.0;
        return uv + float2(-off.x / 366.0, off.y / 613.0);
    }

    // The front parts (material 3): plate, window, wheel and button. The mock's frontVR. `pu` is
    // where the LCD picture is read, and `pic` its color there.
    float3 front(float3 n, float3 vp, float3 vo, float3x3 M, float2 uv, float pt, float3 t, float id, float2 pu, float3 pic) {
        float3 v = normalize(-vp);
        float3 r = reflect(-v, n);
        float3 Ld = normalize(float3(-0.45, 0.55, 0.7));
        float dif = max(dot(n, Ld), 0.0);
        float hi = 1.0 - step(0.5, uv.y);  // ids 250 and 251 live only in the top half
        float body = isId(id, 253.0);
        float rw = length((uv - wheelUV) * float2(732.0, 1226.0));
        float btn = ss(82.7, 81.3, rw);  // the wheel and the button by geometry, with soft edges
        float whl = (1.0 - hi) * ss(225.8, 224.2, rw);
        if (hi < 0.5) body = 1.0 - whl;
        if (pt > 0.5 && pt < 1.5) body = 1.0;  // the plate is all aluminium: its holes are real
        if (btn > 0.5) {  // center button: a shallow dish, its normal leans to the center
            float2 d = (uv - wheelUV) * float2(366.0, -613.0) / 41.0;
            float3 tx = normalize(M * float3(1.0, 0.0, 0.0)), ty = normalize(M * float3(0.0, 1.0, 0.0));
            n = normalize(n - 0.10 * (d.x * tx + d.y * ty));
            r = reflect(-v, n);
            dif = max(dot(n, Ld), 0.0);
            body = 1.0;
        }
        float gz = 1.0 - max(dot(n, v), 0.0);
        // Bead-blasted aluminium: the physical light, with a fine grain in 0.75 pt cells.
        float2 gc = floor(uv * float2(366.0, 613.0) / uGs);
        float gn = fract(sin(dot(gc, float2(12.9898, 78.233))) * 43758.5453);
        float pE = physE(n, vp, vo, M);
        float3 alu = matte(pE) * (1.0 + uGa * (gn - 0.5) * (1.0 - btn));
        alu = mix(alu, min(alu, float3(0.95)), btn);  // the dish never blows out to white
        // The wheel: near white (247, 250, 251) in the same light, with its marks.
        float g = ss(0.85, 0.65, dot(t, float3(0.333)));
        float3 wh = mix(float3(0.969, 0.980, 0.984), t / 0.97, g) * min(pow(0.93 * pE, 0.4545), 1.03);
        float3 col = mix(mix(t * (0.80 + 0.24 * dif) + 0.05 * env(r), wh, mix(step(0.998, id), whl, 1.0 - hi)), alu, body);
        if (hi > 0.5 && isId(id, 250.0) > 0.5) col = float3(0.165, 0.173, 0.180);  // the bezel ink
        float lcd = hi * isId(id, 251.0), win = max(lcd, hi * isId(id, 250.0));
        if (lcd > 0.5) {
            float2 px = pu * float2(732.0, 1226.0);  // past the picture's edge: the dark inner wall
            float inside = step(66.0, px.x) * step(px.x, 666.0) * step(65.0, px.y) * step(px.y, 515.0);
            col = mix(float3(0.10, 0.10, 0.11), pic * (0.80 + 0.24 * dif) + 0.05 * env(r), inside);
            float e = min(min(px.x - 66.0, 666.0 - px.x), min(px.y - 65.0, 515.0 - px.y));  // a soft shade inside the bezel
            col *= mix(0.80, 1.0, ss(0.0, 7.0, e));
        }
        // The LCD: bright and crisp, dimmer at an angle.
        float3 lc = 0.03 + 0.95 * col;
        float va = ss(0.02, 0.20, gz) * uVa;
        lc = mix(lc, float3(0.04, 0.045, 0.05) + 0.16 * lc, va);
        col = mix(col, lc, lcd);
        // The clear window reflects the room: a soft bright patch with a hard edge at an angle.
        float2 qs = r.xy + vp.xy / 520.0;
        float wall = ss(-0.012, 0.012, qs.x * 0.85 + qs.y * 0.55 - 0.10) * ss(0.55, 0.25, qs.y);
        float room = 0.05 + 0.07 * (0.5 + 0.5 * sin(qs.x * 7.0 + qs.y * 4.0)) * (0.5 + 0.5 * sin(qs.y * 9.0 - qs.x * 3.0));
        float rl = mix(room, 0.62, wall) * min(0.06 + 1.5 * gz, 0.75) * uVa;
        col = col + win * float3(rl) * (1.0 - col * 0.6) * mix(0.35, 1.0, lcd + ss(0.05, 0.2, gz));
        return col;
    }

    fragment float4 k3dFragment(K3DVarying in [[stage_in]], constant K3DUniforms& u [[buffer(0)]],
                                texture2d<float> tf [[texture(0)]], texture2d<float> tb [[texture(1)]],
                                texture2d<float> ts [[texture(2)]], sampler sm [[sampler(0)]],
                                sampler sn [[sampler(1)]]) {
        float3x3 M = float3x3(u.mv[0].xyz, u.mv[1].xyz, u.mv[2].xyz);
        float vm = in.vm, pt = in.vpt;
        float2 o = in.vo.xy;
        // The plate's real holes: the screen's rounded rectangle and the wheel's circle. The
        // wheel's own center hole, where the button sits.
        if (pt > 0.5 && pt < 1.5 && vm > 2.5 && vm < 3.5) {
            float2 d = abs(o - float2(0.0, 161.25)) - float2(149.5, 112.25);
            if (length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 7.0 < 0.0 || length(o - float2(0.0, -127.0)) < 112.65) discard_fragment();
        }
        if (pt > 2.5 && pt < 3.5 && length(o - float2(0.0, -127.0)) < 41.65) discard_fragment();

        float3 n = normalize(in.vn);
        float3 v = normalize(-in.vp);
        float3 r = reflect(-v, n);
        float3 Ld = normalize(float3(-0.45, 0.55, 0.7));
        float dif = max(dot(n, Ld), 0.0);
        float3 col;
        if (vm > 9.5) {  // dark: the window's cut edge and the board inside
            col = float3(0.09, 0.095, 0.10) * (0.7 + 0.4 * dif);
        } else if (vm < 0.5) {  // the plate's hole walls: aluminium
            col = matte(physE(n, in.vp, in.vo, M));
        } else if (vm < 1.5) {  // mirror steel, lifted so the dark room does not read as rubber
            float3 s = mix(ts.sample(sm, in.vuv2).rgb, ts.sample(sm, in.vuv).rgb, in.vwt);
            s = 0.22 + 0.78 * s;
            col = mix(s * (0.80 + 0.26 * env(r)), float3(studio(r, in.vp)), 0.84) + 0.18 * pow(max(0.0, 1.0 - abs(dot(n, v))), 6.0);
            col = 0.42 + 0.58 * col;
        } else if (vm < 2.5) {  // the seam: the shadow in the gap
            col = float3(0.16);
        } else if (vm < 3.5) {  // the front parts
            float3 t = tf.sample(sm, in.vuv).rgb;
            float id = tf.sample(sn, in.vuv, level(0)).a;  // the material id, not blended
            float2 pu = lcdUV(n, in.vp, M, in.vuv);
            col = saturate(front(n, in.vp, in.vo, M, in.vuv, pt, t, id, pu, tf.sample(sm, pu).rgb));
            float isL = isId(id, 251.0) * (1.0 - step(0.5, in.vuv.y));
            float rw = length(o - float2(0.0, -127.0));
            if (pt > 2.5 && pt < 3.5) col *= mix(1.0, 0.86, ss(111.6, 112.5, rw));  // the thin gap line round the wheel
            if (pt > 4.5) col *= mix(1.0, 0.88, ss(40.6, 41.5, rw));  // and round the button
            if (u.blk > 0.5) {  // Black: dark plate and button, a black wheel with white marks
                if ((pt > 0.5 && pt < 1.5) || pt > 4.5) col = mix(col * 0.34, col, isL);
                if (pt > 2.5 && pt < 3.5) col = mix(col * 0.12, float3(0.90), ss(0.80, 0.60, dot(t, float3(0.333))));
            }
        } else {  // the back: mirror steel with a frosted etch
            float e = env(r);
            float4 t = tb.sample(sm, in.vuv);
            float3 s = 0.22 + 0.78 * ts.sample(sm, in.vuv).rgb;
            float m = studio(r, in.vp);
            float3 st = mix(s * (0.82 + 0.2 * e), float3(m) * float3(0.985, 0.99, 1.0), 0.92);
            float lum = dot(t.rgb, float3(0.3, 0.59, 0.11));
            float sat = max(t.r, max(t.g, t.b)) - min(t.r, min(t.g, t.b));
            float tone = mix(0.80, 0.30 + 0.52 * ss(0.12, 0.45, lum), ss(0.06, 0.2, sat) * (1.0 - step(2.2, t.r / max(t.g, 0.05))));
            float sl = dot(st, float3(0.33));
            tone = mix(tone, 0.30 + 0.55 * (tone - 0.30), ss(0.35, 0.75, sl));
            col = mix(st, float3(tone * (0.90 + 0.12 * dif)), t.a);
        }
        return float4(col, 1.0);
    }
    """
}
