import Foundation

/// SPIKE (CLA-101): the K.3D.8 shaders in Metal Shading Language, compiled at run time with
/// `makeLibrary(source:)`. K.3D.8 is K.3D.7 with a new Black (charcoal plate with grain and a
/// light fall, a shaded button, a glossy wheel) and a sheen on the Silver wheel: the
/// `bk2` blocks of the About thread's K.3D.8 export (`about/k3d8/export/k3d_src3.js`, 17:06 JST
/// 11-14). Mesh and textures are the same as K.3D.7. The math is `k3d_src3.js` (`data-edge="parts"`, the
/// physical light, `uPhys` 1) for the assembled device, line by line, with its uniforms fixed
/// at the frozen values (`UC` in the mock). Not ported, as the folder's README says: the old
/// light (`uPhys` 0), the other edge options, and everything only Take apart draws (ported
/// from CLA-105, below). CLA-119 ports the 2D layer (`u2d`, `t2`) of mock K.3D.8. The LCD parallax (`lcdUV`) is
/// part of the frozen look and is ported (the README's correction, 23:20 JST 11-13).
///
/// Changes from the mock:
/// - `ss` replaces `smoothstep`, because the mock calls it with edge0 > edge1, which Metal does
///   not define. `ss` is the GLSL formula.
/// - One front texture with mipmaps. The color is read with the mipmapped linear sampler, like
///   the mock's `tm`. The material id (alpha) is read from level 0 with nearest filtering, like
///   the mock's `tf`.
/// - Back faces are culled as in the mock while the device is closed.
/// - CLA-119, the 2D layer: the mock mixes the 2D picture in before the gap lines and the Silver
///   and Black finish; here it is mixed in after them, and `rest` has them too. So at 0° the
///   front is the 2D device exactly, in both colors (the mock's t2 is a Silver picture only).
///   In the LCD the picture moves by the parallax's change from rest, not by all of it: at rest
///   the mock's parallax moves it up to 0.25 pt off the 2D device's screen.
///   The 2D picture is read with nearest filtering when it is magnified, so at 0° each pixel
///   is the picture's own pixel (`K3DRenderer.flatSampler`).
///
/// CLA-105 (Take apart, change 308), PR B: `ex` (0 closed, 1 apart) moves each part along the
/// device's own z, and the shader draws the parts: their inner faces (materials 11 to 45, the
/// mock's `vm>10.5` block, in `inner`), their back faces, and the window glass in a second,
/// blended pass (`pass` 1). Everything new is behind `ex` > 0, or on geometry that only draws
/// then (materials above 10, part 4, back faces), so the closed device is drawn as before. Not
/// yet ported: the fine detail of the inner materials (the mock's lines from "real materials")
/// and the three printed textures (tl, tp, tq). Those parts show their plain color for now.
enum K3DShader {
    /// How far each part moves out along the device's z at `ex` 1, by part (k3d_src3.js vertex
    /// shader): shell, plate, window, wheel, screen module, button, frame, drive, foam, board.
    /// Then the whole device moves back `apartBack`, so it stays in the middle.
    static let apart: [Float] = [0, 240, 285, 277, 196, 313, 130, 62, 127.5, 140.5]
    static let apartBack: Float = 172
    /// CLA-119: within this many degrees of rest, all of the body that shows is the 2D picture.
    static let restAngle = 2.0
    /// CLA-119: the grain's cell on screen, in the scene's pixels: one screen pixel.
    static let grain = Double(K3DRenderer.supersample)

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct K3DUniforms { float4x4 mv; float4x4 pr; float blk; float ex; float pass; float flat; };

    constant float apart[10] = { \(K3DShader.apart.map { "\($0)" }.joined(separator: ", ")) };

    float ss(float e0, float e1, float x) { float t = clamp((x - e0) / (e1 - e0), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }

    struct K3DVarying {
        float4 position [[position]];
        float3 vn; float3 vp; float3 vo; float3 von; float2 vuv; float2 vuv2; float vm; float vwt; float vpt;
    };

    vertex K3DVarying k3dVertex(uint id [[vertex_id]], const device float* data [[buffer(0)]],
                                constant K3DUniforms& u [[buffer(1)]]) {
        const device float* e = data + id * 13;
        float m = e[11], pt = e[12];
        // Take apart: each part moves out along the device's z, then the whole device moves back.
        // The wheel's cable stays tucked behind the wheel until the wheel is clear of the plate
        // (ex .14), then slides out to its place (ex .16 to .6).
        float3 pp = float3(e[0], e[1], e[2]);
        pp.z += u.ex * apart[int(clamp(pt + 0.5, 0.0, 9.0))];
        pp.z -= u.ex * \(K3DShader.apartBack);
        float cb = (pt > 2.5 && pt < 3.5 && ((m > 13.5 && m < 16.5) || (m > 40.5 && m < 41.5))) ? 1.0 : 0.0;
        float cg = 1.0 - ss(0.16, 0.6, u.ex);
        pp.x += cb * 160.0 * cg;
        pp.z -= cb * 2.0 * cg;
        float4 q = u.mv * float4(pp, 1.0);
        float3x3 m3 = float3x3(u.mv[0].xyz, u.mv[1].xyz, u.mv[2].xyz);
        K3DVarying o;
        o.vo = float3(e[0], e[1], e[2]);
        o.vp = q.xyz;
        o.vn = m3 * float3(e[3], e[4], e[5]);
        o.von = float3(e[3], e[4], e[5]);
        o.vuv = float2(e[6], e[7]);
        o.vuv2 = float2(e[8], e[9]);
        o.vwt = e[10];
        o.vm = m;
        o.vpt = pt;
        o.position = u.pr * q;
        // The parts' own geometry (materials above 10) is hidden while closed and for the first
        // 6% of the move: seen edge-on, its thin faces can draw as stray lines.
        if ((u.ex < 0.06 && m > 10.5) || (cb > 0.5 && u.ex < 0.14)) o.position = float4(2.0, 2.0, 2.0, 1.0);
        return o;
    }

    // CLA-119: the 2:1 filter. The scene is drawn at twice the pixels; this pass reads it with
    // a linear sampler at the middle of each 2 x 2 block, which is their mean.
    struct K3DDown { float4 position [[position]]; float2 uv; };

    vertex K3DDown k3dDownVertex(uint id [[vertex_id]], constant float2& scale [[buffer(0)]]) {
        float2 p = float2((id << 1) & 2, id & 2);  // one triangle over the viewport
        K3DDown o;
        o.position = float4(p * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
        o.uv = p * scale;
        return o;
    }

    fragment float4 k3dDownFragment(K3DDown in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) {
        return t.sample(s, in.uv);
    }

    // The frozen light (UC): a lamp fixed in the room, 350 pt left, 800 pt up and 1000 pt out from
    // the front face (z = 34), and the room as a bright ceiling and a darker floor.
    constant float3 lamp = float3(-350.0, 800.0, 34.0 + 1000.0 - 2600.0);
    constant float uKey = 1.08, uCeil = 0.5, uFloor = 0.2, uGs = 0.75, uGa = 0.035, uVa = 0.35;
    constant float3 uTint = float3(0.995, 0.997, 1.0);
    constant float2 wheelUV = float2(366.0 / 732.0, 867.0 / 1226.0);

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
    float3 front(float3 n, float3 vp, float3 vo, float3x3 M, float2 uv, float pt, float3 t, float id, float2 pu, float3 pic, float2 gu) {
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
        float2 gc = floor(gu * float2(366.0, 613.0) / uGs);
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

    // Take apart: the parts' inner faces and the inside of the device (materials 11 to 45), plain
    // colors lit by the physical light. The mock's `vm>10.5` block. `glass` is 1 in the window's
    // clear middle. CLA-105 B2: the mock's "real materials" detail (k3d_src3.js, Jason 23:04 JST
    // 11-13 and later): flex traces, the board's parts and white print, the drive's metal, shadows
    // where parts lie on each other, and the edge light. The printed textures (tl, tp, tq) come
    // in B3: until then their places show the plain material.
    float rIn(float2 o, float x0, float x1, float y0, float y1) { return min(min(o.x - x0, x1 - o.x), min(o.y - y0, y1 - o.y)); }
    float sdQ(float2 p, float2 a, float2 b) { float2 d = abs(p - (a + b) * 0.5) - abs(b - a) * 0.5; return max(d.x, d.y); }
    // The mock's `bxf`: a printed outline box.
    float printBox(float2 o, float x0, float x1, float y0, float y1) { return ss(0.5, 0.15, abs(rIn(o, x0, x1, y0, y1))); }
    float hash2(float2 p, float2 k, float m) { return fract(sin(dot(p, k)) * m); }
    // The shell's flat ribbon (the mock's `dB`): its distance, square corners.
    float ribbon(float2 o) {
        float d = min(sdQ(o, float2(-158.0, 223.0), float2(-119.0, 223.0)), sdQ(o, float2(-12.0, 10.0), float2(173.0, 10.0)));
        d = min(d, sdQ(o, float2(-119.0, 262.0), float2(-119.0, 179.0)));
        d = min(d, sdQ(o, float2(-119.0, 179.0), float2(-39.0, 179.0)));
        d = min(d, sdQ(o, float2(-39.0, 179.0), float2(-39.0, 151.0)));
        d = min(d, sdQ(o, float2(-39.0, 151.0), float2(131.0, 151.0)));
        d = min(d, sdQ(o, float2(131.0, 129.0), float2(131.0, 180.0)));
        d = min(d, sdQ(o, float2(-12.0, 129.0), float2(131.0, 129.0)));
        return min(d, sdQ(o, float2(-12.0, 129.0), float2(-12.0, 10.0)));
    }
    // The logic board's front: fine traces, small parts, pads and white print (Jason 13:27 and
    // 13:54 JST 11-14). `fr0` is 1 on its front face.
    float3 boardDetail(float3 c, float2 o, float2 w, float rho, float fr0) {
        float clr = min(step(56.0, rho) + step(0.5, 1.0 - fr0), 1.0);  // the center disc on the front stays clean
        float2 tf = fract(o / float2(26.0, 19.0));
        float th = hash2(floor(o / float2(26.0, 19.0)), float2(41.3, 17.7), 9173.3);
        float trA = step(abs(tf.y - 0.5), 0.035) * step(0.1, tf.x) * step(tf.x, 0.5 + 0.4 * th);
        float trB = step(abs(tf.x - 0.5 - 0.4 * th), 0.03) * step(tf.y, 0.5) * step(0.12, tf.y);
        c = mix(c, c + float3(0.045, 0.05, 0.045), min(step(th, 0.55) * (trA + trB), 1.0) * clr);
        float2 sf = fract(o / float2(7.0, 5.0));
        float s1 = hash2(floor(o / float2(7.0, 5.0)), float2(27.17, 91.3), 5831.7);
        float s2 = hash2(floor(o / float2(42.0, 25.0)), float2(3.1, 7.7), 311.7);
        float sk = step(s2, 0.50) * step(s1, mix(0.26, 0.12, fr0)) * step(0.15, sf.x) * step(sf.x, 0.25 + 0.6 * s1 / 0.26) * step(abs(sf.y - 0.5), 0.11);
        c = mix(c, float3(0.70, 0.72, 0.70), 0.62 * sk * clr);
        float2 pf = fract(o / float2(9.0, 7.0)) - 0.5;
        float ph = hash2(floor(o / float2(9.0, 7.0)), float2(71.9, 33.1), 2713.9);
        float zin = fr0 * step(rho, 100.0);
        float zR = step(96.0, o.x) * step(-190.0, o.y) * step(o.y, -70.0);
        float zL = step(o.x, -96.0) * step(o.y, -170.0) * step(-230.0, o.y);
        float zd = fr0 * max(zR, zL);
        c += float3(0.012, 0.015, 0.012) * zd;
        float pp = step(mix(mix(0.87, 0.955, zin), 0.72, zd), ph) * step(abs(pf.x), 0.28) * step(abs(pf.y), 0.20);
        float3 body = ph > 0.94 ? float3(0.42, 0.33, 0.22) : float3(0.13, 0.13, 0.14);
        c = mix(c, mix(body, float3(0.80, 0.80, 0.78), step(0.17, abs(pf.x))), pp * clr);
        if (fr0 < 0.5) return c;
        float pr = max(max(printBox(o, -157.0, -99.0, -66.0, -18.0), printBox(o, -158.0, -122.0, -165.0, -103.0)), printBox(o, 22.0, 45.0, -62.0, -36.0));
        pr = max(pr, max(max(printBox(o, 40.0, 104.0, -251.0, -231.0), printBox(o, 98.0, 138.0, -278.0, -267.0)), printBox(o, -60.0, -22.0, -207.0, -176.0)));
        pr = max(pr, max(max(printBox(o, 110.0, 138.0, -208.5, -192.5), printBox(o, 110.0, 138.0, -244.5, -228.5)), printBox(o, 100.0, 156.0, -66.0, -16.0)));
        pr *= step(3.6, abs(max(rho - 104.0, w.y - 97.0)));
        c = mix(c, float3(0.76, 0.78, 0.76), 0.74 * pr);  // the printed labels' text (tp) comes in B3
        float2 vq = o / 6.5, vf = fract(vq) - 0.5;
        float vh = hash2(floor(vq), float2(17.1, 61.7), 7741.3);
        float vreg = step(abs(o.x + 57.0), 32.0) * step(abs(o.y + 86.0), 22.0);
        float vd = length(vf - 0.3 * (float2(vh, fract(vh * 7.0)) - 0.5));
        return mix(c, float3(0.78, 0.80, 0.78), step(mix(0.90, 0.45, vreg), vh) * ss(0.20, 0.14, vd) * clr);
    }

    float3 inner(float id, float3 n, float3 v, float3 r, float3 vp, float3 vo, float3 von, float3x3 M, float pt, float blk, float ex, float glass) {
        float g = pow(clamp(physE(n, vp, vo, M), 0.0, 2.0), 0.4545);
        float2 o = vo.xy, w = o - float2(0.0, -127.0);
        float rho = length(w);
        float3 h = normalize(normalize(float3(lamp.x, lamp.y, 1000.0)) + v);
        float sp = pow(max(dot(n, h), 0.0), 30.0);
        float3 c = float3(0.5);
        if (id == 11.0) c = float3(0.33, 0.40, 0.50);  // battery
        else if (id == 12.0) c = float3(0.72, 0.73, 0.75) * (0.985 + 0.015 * sin(o.y * 2.3)) + 0.25 * sp;  // drive, shield can: brushed metal
        else if (id == 13.0) c = float3(0.055, 0.06, 0.065) + float3(0.05, 0.04, 0.02) * step(0.86, fract(o.x * 0.11 + floor(o.y * 0.035) * 0.37)) * step(0.3, fract(o.y * 0.035)) + 0.06 * sp;  // logic board
        else if (id == 14.0) c = float3(0.17, 0.17, 0.18) + 0.14 * sp;  // chips
        else if (id == 41.0) c = float3(0.17, 0.17, 0.18) + 0.06 * sp;  // chip label (its print: tl, later)
        else if (id == 15.0) c = float3(0.86, 0.68, 0.30) + 0.35 * sp;  // gold
        else if (id == 16.0) c = float3(0.84, 0.50, 0.16) * (0.90 + 0.10 * step(0.5, fract(o.x * 0.25)));  // ribbon cable
        else if (id == 17.0) c = float3(0.66, 0.67, 0.69) + 0.20 * sp;  // LCD panel frame
        else if (id == 18.0) c = float3(0.52, 0.33, 0.12);  // flex pad
        else if (id == 19.0) c = float3(0.90, 0.90, 0.88);  // battery print (tl, later)
        else if (id == 20.0) c = float3(0.80, 0.78, 0.70) * (0.96 + 0.04 * sin(o.x * 5.0)) + 0.12 * sp;
        else if (id == 45.0) c = float3(0.52, 0.40, 0.26) + 0.14 * sp;  // connector latch
        else if (id == 21.0) {  // plate inner skin: raw aluminium, a black strip round the window, a red-brown sheet round the wheel
            c = uTint * 0.72 * (blk > 0.5 ? 0.34 : 1.0);
            float2 d = abs(o - float2(0.0, 161.25)) - float2(149.5, 112.25);
            float wd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 7.0;
            float2 e = abs(o - float2(0.0, -137.0)) - float2(148.0, 137.0);
            float sd = length(max(e, 0.0)) + min(max(e.x, e.y), 0.0) - 12.0;
            c = mix(c, float3(0.56, 0.33, 0.17), ss(0.6, -0.6, sd) * ss(118.0, 119.2, rho) * (1.0 - step(abs(o.x + 4.0), 84.0) * step(-34.0, o.y))
                * (1.0 - step(o.y, -268.0) * step(abs(abs(o.x) - 110.0), 13.0)));
            c = mix(c, float3(0.07, 0.07, 0.08), ss(12.6, 11.4, wd));
        }
        else if (id == 22.0) c = float3(0.78, 0.86, 0.84) + 0.25 * sp;  // window cut edge: clear plastic
        else if (id == 23.0) c = mix(float3(0.10, 0.11, 0.12), float3(0.60, 0.64, 0.68), glass);  // window back: ink border, clear glass
        else if (id == 24.0) {  // wheel back: plastic with a moulded line (its print: tq, later)
            c = (blk > 0.5 ? float3(0.13) : float3(0.90, 0.91, 0.92)) * mix(1.0, 0.93, ss(1.2, 0.0, abs(rho - 100.0)));
            c *= 1.0 - 0.07 * ss(1.3, 0.4, rho * abs(sin(atan2(w.y, w.x) * 4.0 + 1.5708)) / 4.0) * step(50.0, rho) * step(rho, 99.0);
        }
        else if (id == 25.0) c = (blk > 0.5 ? float3(0.16) : float3(0.62, 0.63, 0.65)) * mix(1.0, 0.72, ss(8.5, 7.5, rho));  // button back
        else if (id == 28.0) c = blk > 0.5 ? float3(0.13) : float3(0.92, 0.93, 0.94);  // wheel side and center hole wall
        else if (id == 29.0) c = blk > 0.5 ? float3(0.16) : float3(0.62, 0.63, 0.65);  // button side
        else if (id == 34.0) c = float3(0.80, 0.81, 0.83) * (0.985 + 0.015 * sin(o.y * 1.3)) + 0.12 * sp;  // shell inner wall: brushed steel
        else if (id == 35.0) c = float3(0.13, 0.36, 0.78);  // battery wrap
        else if (id == 36.0) {  // drive bumpers: grey foam
            float fh = fract(sin(dot(floor(vo * 1.9), float3(12.9898, 78.233, 37.719))) * 43758.5453);
            float fh2 = fract(sin(dot(floor(vo * 0.7), float3(39.3, 11.1, 57.7))) * 4375.5);
            c = float3(0.50, 0.51, 0.49) * (0.86 + 0.14 * fh) * (0.95 + 0.05 * fh2);
            if (pt < 0.5) c *= 0.24;
        }
        else if (id == 37.0) c = float3(0.50, 0.76, 0.90) * (0.94 + 0.06 * fract(sin(dot(floor(o * 0.6), float2(12.9898, 78.233))) * 43758.5453));  // blue foam
        else if (id == 38.0) {  // gold switch with its dark center
            float d = min(min(length(w), length(abs(w) - float2(78.0, 0.0))), length(abs(w) - float2(0.0, 78.0)));
            c = mix(float3(0.05, 0.045, 0.04), float3(0.86, 0.61, 0.13) * (0.80 + 0.30 * ss(8.0, 11.5, d)) * (1.0 - 0.42 * ss(12.5, 14.0, d)), ss(7.2, 8.1, d)) + 0.28 * sp;
        }
        else if (id == 44.0) c = float3(0.085, 0.09, 0.09) + 0.10 * sp;  // switch base
        else if (id == 39.0) {  // the pale ring round the center switch
            c = mix(float3(0.17, 0.18, 0.185), float3(0.80, 0.82, 0.80), ss(0.7, 0.0, abs(rho - 37.0) - 4.5));
            c = mix(c, float3(0.80, 0.82, 0.80), step(abs(abs(w.x) - abs(w.y)), 2.0) * step(abs(rho - 42.5), 1.6));
        }
        else if (id == 42.0) {  // yellow label with a square code
            c = float3(0.88, 0.80, 0.20);
            float2 q = o - float2(-45.0, -60.5);
            if (max(abs(q.x), abs(q.y)) < 17.0) {
                float k = fract(sin(dot(floor(q / 2.6), float2(12.9898, 78.233))) * 43758.5453);
                c = mix(c, float3(0.10), step(0.52, k) * step(max(abs(q.x), abs(q.y)), 15.6));
            }
        }
        else if (id == 43.0) c = mix(float3(0.10, 0.10, 0.09), float3(0.24, 0.21, 0.14), step(0.5, fract(vo.z * 0.9)));  // board edge: layers
        else if (id == 40.0) c = float3(0.72, 0.73, 0.75);  // drive back: metal (its label: tl, later)
        else if (id == 30.0) c = float3(0.74, 0.75, 0.76) * (0.975 + 0.025 * fract(sin(dot(floor(o * 1.3), float2(12.9898, 78.233))) * 43758.5453));  // frame: cast metal
        else if (id == 31.0) c = float3(0.46, 0.48, 0.49);  // frame floor
        else if (id == 32.0) c = float3(0.66, 0.67, 0.68) * (0.99 + 0.01 * sin(o.x * 1.7)) + 0.12 * sp;  // shield plate
        else if (id == 33.0) c = float3(0.76, 0.77, 0.78) + 0.25 * sp;  // the plate's steel clips
        else if (id == 26.0) c = float3(0.16, 0.36, 0.70);  // blue rubber corners
        else if (id == 27.0) {  // LCD back: metal, a plain label, the flex tail
            c = float3(0.66, 0.67, 0.69) * (0.96 + 0.04 * sin(o.x * 2.1)) + 0.20 * sp;
            float2 l = abs(o - float2(0.0, 176.0)) - float2(70.0, 26.0);
            c = mix(c, float3(0.88, 0.88, 0.86), step(max(l.x, l.y), 0.0));
            c = mix(c, float3(0.52, 0.33, 0.12), step(o.y, 62.0) * step(abs(o.x), 60.0));
        }
        // Metals reflect the room; the inside is darker until the parts are well apart.
        float fz = step(0.9, abs(von.z)), fr0 = step(0.0, von.z), nh = max(dot(n, h), 0.0);
        float mt = 0.0, ed = 99.0, sh = 1.0;
        if (id == 12.0 || id == 17.0 || id == 27.0 || id == 32.0 || id == 33.0 || id == 34.0 || id == 40.0) mt = 1.0;
        else if (id == 30.0 || id == 31.0) mt = 0.55;
        // CLA-105 B2: the mock's real materials.
        if (id == 16.0 && pt < 0.5) c = float3(0.84, 0.66, 0.24);
        if (pt < 0.5 && id == 16.0 && o.x > 79.0 && o.y > 195.0)
            c = float3(0.80, 0.46, 0.13) * (0.90 + 0.10 * step(0.5, fract(o.x * 0.9))) * (0.94 + 0.06 * step(0.5, fract(o.y * 0.45)));
        if (pt < 0.5 && id == 12.0 && o.x > 83.0 && o.y > 213.0) {  // the jack and hold block: brushed steel, a round sleeve, screw heads
            float bs = fract(sin(floor(o.x * 9.0) * 12.9898) * 43758.5453);
            c *= (0.80 + 0.10 * bs) * (0.86 + 0.30 * ss(214.0, 284.0, o.y));
            if (o.y > 264.0 && o.x > 118.0 && o.x < 136.0 && fz > 0.5) c *= 0.55 + 0.75 * pow(sin(3.14159 * (o.x - 118.0) / 18.0), 1.5);
            float ds = min(length(o - float2(93.0, 275.0)), length(o - float2(143.0, 275.0)));
            if (ds < 3.5) c *= 0.78 + 0.22 * ss(1.5, 3.4, ds); else c *= 1.0 - 0.25 * (1.0 - ss(3.5, 4.6, ds));
        }
        if (id == 16.0 && pt > 3.5 && pt < 4.5 && o.y < 24.0 && o.y > 5.0 && o.x > -66.0 && o.x < 84.0) c = float3(0.46, 0.63, 0.86);
        if (id == 37.0) c += float3(0.16) * step(0.965, hash2(floor(o * 1.7), float2(39.3, 11.1), 4375.5));
        if (id == 16.0 || id == 18.0 || id == 26.0 || id == 37.0) c = mix(float3(dot(c, float3(0.30, 0.59, 0.11))), c, 0.70);
        if (id == 35.0) c += 0.15 * pow(nh, 8.0) + 0.05 * ss(-0.3, 0.8, r.y);
        if (id == 16.0 || id == 18.0) c += float3(0.14, 0.11, 0.06) * pow(nh, 10.0);
        if (id == 26.0) c += 0.06 * pow(nh, 6.0);
        if (id == 13.0 && fz > 0.5) {  // the board: gold pads and small parts
            float2 cf = fract(o / 11.0) - 0.5;
            float hs = hash2(floor(o / 11.0), float2(12.9898, 78.233), 43758.5453);
            c = mix(c, mix(float3(0.80, 0.63, 0.28), float3(0.74, 0.76, 0.74), step(8.5, pt)), step(0.93, hs) * ss(0.15, 0.10, length(cf)));
            float cp = step(hs, 0.045 * (1.0 - 0.7 * step(8.5, pt) * fr0 * step(rho, 100.0))) * step(abs(cf.x), 0.30) * step(abs(cf.y), 0.15);
            c = mix(c, mix(float3(0.50, 0.41, 0.30), float3(0.78, 0.78, 0.76), step(0.19, abs(cf.x))), cp);
            c += 0.035 * ss(-0.4, 0.8, r.y);
        }
        if (id == 13.0 && pt > 8.5 && fz > 0.5) c = boardDetail(c, o, w, rho, fr0);
        if (id == 12.0 && pt > 6.5 && pt < 7.5) {  // the drive: fine brushing and a pressed ring
            c *= 0.93 + 0.05 * sin(o.y * 8.3) + 0.03 * sin(o.y * 21.7 + o.x * 0.02);
            float rb = length(o - float2(0.0, 34.0));
            c *= 1.0 + 0.10 * ss(1.4, 0.0, abs(rb - 57.0)) * step(0.9, von.z) - 0.06 * ss(1.4, 0.0, abs(rb - 59.6)) * step(0.9, von.z);
        }
        if (id == 32.0 && fz > 0.5) ed = rIn(o, -158.0, 158.0, 40.0, 284.0);
        if (id == 40.0) {  // the drive's back: screw holes and a pressed edge
            float2 sq = float2(abs(o.x) - 144.0, abs(o.y + 80.0) - 196.0);
            float sl = length(sq);
            if (sl < 5.2) {
                c = mix(c * 0.50, float3(0.80, 0.81, 0.83), ss(4.4, 3.7, sl));
                c *= 1.0 - 0.55 * step(min(abs(sq.x), abs(sq.y)), 0.55) * step(sl, 2.7);
            }
            float2 d = abs(o - float2(0.0, -80.0)) - float2(146.0, 198.0);
            float2 gd = d.x > d.y ? float2(sign(o.x), 0.0) : float2(0.0, sign(o.y + 80.0));
            c *= 1.0 + 0.10 * ss(1.6, 0.0, abs(max(d.x, d.y) + 8.0)) * dot(gd, float2(-0.4, 0.9));
            ed = rIn(o, -156.0, 156.0, -288.0, 128.0);
        }
        if (id == 27.0 && fz > 0.5) {  // the LCD's back: its edge and a pressed step
            float2 d = abs(o - float2(0.0, 161.5)) - float2(150.0, 112.0);
            ed = -(length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 4.0);
            float2 e2 = abs(o - float2(0.0, 161.5)) - float2(136.0, 98.0);
            float2 gd = e2.x > e2.y ? float2(sign(o.x), 0.0) : float2(0.0, sign(o.y - 161.5));
            c *= 1.0 + 0.09 * ss(1.6, 0.0, abs(max(e2.x, e2.y))) * dot(gd, float2(-0.4, 0.9));
        }
        if (id == 35.0 && fz > 0.5) ed = rIn(o, -156.0, 80.0, 164.0, 256.0);
        if (id == 13.0 && fz > 0.5) {  // the board: its edge, and the shadows of the parts on it
            if (pt > 6.5 && pt < 7.5) {
                ed = rIn(o, -140.0, 140.0, -272.0, -66.0);
                sh *= mix(0.58, 1.0, ss(0.0, 6.0, -rIn(o, -60.0, 40.0, -200.0, -120.0))) * mix(0.58, 1.0, ss(0.0, 6.0, -rIn(o, 64.0, 124.0, -150.0, -90.0)));
            } else {
                ed = rIn(o, -162.0, 162.0, -290.0, -14.0);
                if (fr0 > 0.5) {
                    float2 a = abs(w);
                    float ds = min(max(a.x, a.y), min(max(abs(a.x - 78.0), a.y), max(a.x, abs(a.y - 78.0)))) - 17.0;
                    sh *= mix(0.55, 1.0, ss(0.0, 5.0, ds));
                    sh *= mix(0.58, 1.0, ss(0.0, 6.0, -rIn(o, -150.0, -118.0, -262.0, -230.0))) * mix(0.55, 1.0, ss(0.0, 8.0, -rIn(o, -166.0, -146.0, -96.0, -58.0)));
                    // The brown glue ring round the wheel's switches, and its pale edge.
                    float dT = max(rho - 104.0, w.y - 97.0), an = atan2(w.y, w.x);
                    float bi = 2.9 + 0.45 * sin(an * 7.0) + 0.25 * sin(an * 23.0 + 1.7) - abs(dT);
                    float3 glue = float3(0.31, 0.165, 0.07) * (1.0 + 0.16 * sin(an * 61.0) * sin(rho * 3.1)) * mix(0.72, 1.0, ss(0.0, 0.9, bi));
                    c = mix(c, glue, 0.9 * ss(0.0, 0.8, bi) * step(-286.0, o.y));
                    c = mix(c, float3(0.70, 0.72, 0.70), 0.5 * ss(0.55, 0.2, abs(max(rho - 110.5, w.y - 103.0))) * step(-286.0, o.y));
                } else {
                    sh *= mix(0.58, 1.0, ss(0.0, 7.0, -rIn(o, -135.0, -99.0, -202.0, -164.0))) * mix(0.58, 1.0, ss(0.0, 7.0, -rIn(o, 5.0, 56.0, -202.0, -142.0)));
                    sh *= mix(0.58, 1.0, ss(0.0, 7.0, -rIn(o, 93.0, 148.0, -202.0, -145.0))) * mix(0.6, 1.0, ss(0.0, 7.0, -rIn(o, -52.0, 52.0, -296.0, -252.0)));
                }
            }
        }
        if (id == 39.0) {
            float2 a = abs(w);
            float ds = min(max(a.x, a.y), min(max(abs(a.x - 78.0), a.y), max(a.x, abs(a.y - 78.0)))) - 17.0;
            sh *= mix(0.85, 1.0, ss(0.0, 5.0, ds));
        }
        if (id == 31.0) sh *= 0.80;
        if (id == 34.0 && fz > 0.5) {  // the shell floor: shadows of the battery and the jack block
            float2 d = abs(o) - float2(147.0, 270.5);
            float sb = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 30.0;
            sh *= mix(0.60, 1.0, ss(0.0, 24.0, -sb));
            sh *= mix(0.50, 1.0, ss(0.0, 16.0, -rIn(o, -156.0, 80.0, 164.0, 256.0))) * mix(0.55, 1.0, ss(0.0, 11.0, -rIn(o, 84.0, 150.0, 214.0, 284.0)));
            sh *= mix(0.70, 1.0, ss(0.0, 5.0, -rIn(o, 104.0, 146.0, 180.0, 214.0)));
        }
        if (id == 34.0 && fz > 0.5 && fr0 > 0.5) {  // the shell's wide flat ribbon (Jason 00:18 JST 11-14); its print (tl) comes in B3
            float dB = ribbon(o);
            sh *= mix(0.70, 1.0, ss(10.3, 14.0, dB));
            float cbw = ss(10.5, 9.7, dB);
            c = mix(c, float3(1.30, 0.74, 0.20) * (0.88 + 0.12 * ss(0.4, 1.4, abs(dB - 7.6))), cbw);
            mt *= 1.0 - cbw;
        }
        if (id == 21.0) {
            float2 d = abs(o) - float2(149.0, 272.5);
            sh *= mix(0.72, 1.0, ss(0.0, 16.0, -(length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 34.0)));
        }
        if (id != 22.0 && id != 23.0) sh *= mix(0.62, 1.0, ss(0.06, 0.75, ex));
        float eg = fz * ss(1.4, 0.0, ed) * (0.14 + 0.16 * mt);
        float brl = fract(sin(floor(o.x * 3.0) * 12.9898) * 43758.5453);
        float sr = 0.46 + 0.30 * ss(-0.7, 0.7, r.y) + 0.42 * pow(max(dot(r, normalize(float3(-0.45, 0.5, 0.75))), 0.0), 5.0)
            + 0.10 * ss(0.2, 0.95, dot(r, normalize(float3(0.7, 0.1, 0.7))));
        float mm = 0.60 * mt;
        if (id == 34.0) { sr = mix(sr, 0.50 + 0.75 * studio(r, vp), 0.7); mm = 0.85; }
        if (id == 12.0 && pt > 6.5 && pt < 7.5) { sr = mix(sr, 0.50 + 0.75 * studio(r, vp), 0.65); mm = 0.82; }
        return c * mix(float3(g), float3(sr * 1.18), mm) * (1.0 + 0.045 * mt * (brl - 0.5)) * sh * (1.0 + eg);
    }

    // The front parts (material 3) as lit at the pose: `front`, then the window apart, the gap
    // lines and the Silver and Black finish. CLA-119: one function, so the 2D layer can light
    // the same point at the rest pose too.
    float3 frontPart(float3 n, float3 vp, float3 vo, float3x3 M, float2 uv, float pt, float3 t, float id, float2 pu, float3 pic,
                     float blk, float ex, float2 gu, float2 go) {
        float3 v = normalize(-vp);
        float3 r = reflect(-v, n);
        float dif = max(dot(n, normalize(float3(-0.45, 0.55, 0.7))), 0.0);
        float fr = pow(1.0 - max(dot(n, v), 0.0), 3.0);
        float2 o = vo.xy;
        float3 col = saturate(front(n, vp, vo, M, uv, pt, t, id, pu, pic, gu));
        float isL = isId(id, 251.0) * (1.0 - step(0.5, uv.y));
        if (ex > 0.0 && pt > 1.5 && pt < 2.5)  // apart: the window is clear glass once the screen has moved out
            col = mix(col, float3(0.78, 0.82, 0.86) * (0.5 + 0.4 * fr) + 0.12 * env(r), isL * ss(0.0, 0.25, ex));
        if (pt > 3.5 && pt < 4.5) col = mix(float3(0.10, 0.11, 0.12) * (0.7 + 0.4 * dif), col, isL);  // the screen module round its LCD
        float rw = length(o - float2(0.0, -127.0));
        if (pt > 2.5 && pt < 3.5) col *= mix(1.0, 0.86, ss(111.6, 112.5, rw));  // the thin gap line round the wheel
        if (pt > 4.5) col *= mix(1.0, 0.88, ss(40.6, 41.5, rw));  // and round the button
        if (blk < 0.5 && pt > 2.5 && pt < 3.5) {  // K.3D.8 Silver wheel: a weak sheen, a soft shade at the rim and the hole
            col *= 0.955 + 0.055 * env(r);
            col *= 1.0 - 0.055 * ss(108.0, 112.0, rw) - 0.045 * ss(46.0, 42.5, rw);
        }
        if (blk > 0.5) {  // K.3D.8 Black: charcoal plate with grain and a light fall, a shaded button, a glossy black wheel
            float L = dot(col, float3(0.333));
            float2 d = o - float2(0.0, -127.0);
            if ((pt > 0.5 && pt < 1.5) || pt > 4.5) {
                float gn = fract(sin(dot(floor(go * 3.0), float2(12.9898, 78.233))) * 43758.5453);  // grain, one cell per 1/3 pt
                float3 ch = float3(0.285, 0.290, 0.303) * pow(L / 0.80, 1.7) * (0.86 + 0.30 * ss(-300.0, 300.0, o.y)) * (0.97 + 0.06 * gn);
                if (pt > 4.5) ch *= 0.84 * (1.0 - 0.12 * d.y / 41.0) * (1.0 - 0.07 * dot(d, d) / 1681.0);
                col = mix(ch, col, isL);  // the screen surround keeps its look
            }
            if (pt > 2.5 && pt < 3.5) {
                float3 wb = float3(0.040, 0.041, 0.046) * (0.7 + 0.6 * L) + 0.085 * env(r) * ss(0.2, 0.9, L)
                    + 0.05 * ss(107.5, 111.5, rw) + 0.03 * ss(46.0, 42.5, rw);
                col = mix(wb, float3(0.93), ss(0.80, 0.60, dot(t, float3(0.333))));  // white marks
            }
        }
        return col;
    }

    // CLA-119, the 2D layer: where the point shows at rest, as uv of the 2D picture. The wheel and
    // the button sit up to 1.6 pt behind the front plane, so they show a little smaller.
    float2 restUV(float3 vo) {
        float2 rp = vo.xy * (2600.0 - \(K3DMesh.depth / 2)) / (2600.0 - vo.z);
        return float2(rp.x / 366.0 + 0.5, 0.5 - rp.y / 613.0);
    }

    // The 2D picture at `fu`, straight alpha, with the 2D device's round corner cut at `ru`.
    float4 flatAt(texture2d<float> t2, sampler sf, float2 fu, float2 ru) {
        float4 f2 = t2.sample(sf, fu);
        f2.rgb /= max(f2.a, 1.0 / 255.0);  // the picture is premultiplied
        float2 cq = abs(ru * float2(732.0, 1226.0) - float2(366.0, 613.0)) - float2(298.0, 545.0);
        f2.a *= ss(68.5, 67.0, length(max(cq, 0.0)));
        return f2;
    }

    fragment float4 k3dFragment(K3DVarying in [[stage_in]], constant K3DUniforms& u [[buffer(0)]],
                                texture2d<float> tf [[texture(0)]], texture2d<float> tb [[texture(1)]],
                                texture2d<float> ts [[texture(2)]], sampler sm [[sampler(0)]],
                                sampler sn [[sampler(1)]], texture2d<float> t2 [[texture(3)]], sampler sf [[sampler(2)]],
                                bool ff [[front_facing]]) {
        float3x3 M = float3x3(u.mv[0].xyz, u.mv[1].xyz, u.mv[2].xyz);
        float vm = in.vm, pt = in.vpt;
        // CLA-119: the plate's grain is read once per screen pixel, at its middle, as the mock
        // reads it at 2 px per pt. The scene is drawn at `K3DRenderer.supersample` x; read at
        // each of its samples, the filter down would average the grain 20 to 40% weaker.
        float2 gx = floor(in.position.xy / \(grain)) * \(grain) + \(grain / 2) - in.position.xy;
        float2 gu = in.vuv + dfdx(in.vuv) * gx.x + dfdy(in.vuv) * gx.y;
        float2 go = in.vo.xy + dfdx(in.vo.xy) * gx.x + dfdy(in.vo.xy) * gx.y;
        // CLA-119: 1 at rest, 0 from `restAngle` (2°) off it, smooth in degrees, as the 2D
        // device's own fade (`K3DFlip.nearRest`). The body's z toward the eye is the angle's cosine.
        float nearRest = 1.0 - ss(0.0, \(K3DShader.restAngle), acos(min(u.mv[2].z, 1.0)) * \(180 / Double.pi));
        float2 o = in.vo.xy;
        // The window's clear middle (the LCD id in the front texture's top half).
        float glass = isId(tf.sample(sn, in.vuv, level(0)).a, 251.0) * (1.0 - step(0.5, in.vuv.y));
        // Apart, the window's clear middle is see-through: pass 1 draws it alone, blended, after
        // everything else; pass 0 leaves it out. Closed, there is one pass and nothing changes.
        float oA = 1.0;
        if (u.ex > 0.0005) {
            float isG = (pt > 1.5 && pt < 2.5 && ((vm > 2.5 && vm < 3.5) || (vm > 22.5 && vm < 23.5))) ? glass : 0.0;
            if ((u.pass < 0.5 && isG > 0.5) || (u.pass > 0.5 && isG < 0.5)) discard_fragment();
            if (u.pass > 0.5) {
                float3 nn = ff ? normalize(in.vn) : -normalize(in.vn);
                oA = (0.10 + 0.55 * pow(1.0 - max(dot(nn, normalize(-in.vp)), 0.0), 3.0)) * ss(0.0, 0.25, u.ex);
            }
        }
        // The plate's real holes: the screen's rounded rectangle and the wheel's circle. The
        // wheel's own center hole, where the button sits.
        if (pt > 0.5 && pt < 1.5 && vm > 2.5 && vm < 3.5) {
            float2 d = abs(o - float2(0.0, 161.25)) - float2(149.5, 112.25);
            if (length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 7.0 < 0.0 || length(o - float2(0.0, -127.0)) < 112.65) discard_fragment();
        }
        if (pt > 0.5 && pt < 1.5 && vm > 20.5 && vm < 21.5) {  // and in its inner skin
            float2 d = abs(o - float2(0.0, 161.25)) - float2(149.5, 112.25);
            if (length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 7.0 < 0.0 || length(o - float2(0.0, -127.0)) < 112.65) discard_fragment();
        }
        if (pt > 2.5 && pt < 3.5 && length(o - float2(0.0, -127.0)) < 41.65) discard_fragment();
        if (pt > 0.5 && pt < 1.5 && vm < 0.5 && u.ex > 0.0005 && in.vo.z < \(K3DMesh.depth / 2 - 2.2)) discard_fragment();  // apart: the wheel hole's wall is a short collar
        if (pt < 0.5 && vm > 9.5 && vm < 10.5 && u.ex >= 0.06) discard_fragment();  // apart: the shell is open (its dark cover is for the closed device)
        if (pt > 8.5 && ((vm > 12.5 && vm < 13.5) || (vm > 42.5 && vm < 43.5))) {  // the logic board's real outline
            if ((o.y > -17.0 && length(o - float2(0.0, -127.0)) > 121.0) || (o.y < -281.0 && abs(o.x) > 118.0)) discard_fragment();
        }

        float3 n = ff ? normalize(in.vn) : -normalize(in.vn);  // apart, back faces draw too
        float3 v = normalize(-in.vp);
        float3 r = reflect(-v, n);
        float3 Ld = normalize(float3(-0.45, 0.55, 0.7));
        float dif = max(dot(n, Ld), 0.0);
        float fr = pow(1.0 - max(dot(n, v), 0.0), 3.0);
        float3 col;
        if (vm > 10.5) {  // Take apart: the parts' inner faces
            col = inner(floor(vm + 0.5), n, v, r, in.vp, in.vo, in.von, M, pt, u.blk, u.ex, glass);
        } else if (vm > 9.5) {  // dark: the window's cut edge and the board inside
            col = float3(0.09, 0.095, 0.10) * (0.7 + 0.4 * dif);
            if (u.ex > 0.0 && pt > 1.5 && pt < 2.5)  // apart: the window's cut edge is clear plastic
                col = mix(col, float3(0.78, 0.86, 0.84) * pow(clamp(physE(n, in.vp, in.vo, M), 0.0, 2.0), 0.4545), ss(0.0, 0.25, u.ex));
        } else if (vm < 0.5) {  // the plate's hole walls: aluminium
            col = matte(physE(n, in.vp, in.vo, M));
        } else if (vm < 1.5) {  // mirror steel, lifted so the dark room does not read as rubber
            float3 s = mix(ts.sample(sm, in.vuv2).rgb, ts.sample(sm, in.vuv).rgb, in.vwt);
            s = 0.22 + 0.78 * s;
            col = mix(s * (0.80 + 0.26 * env(r)), float3(studio(r, in.vp)), 0.84) + 0.18 * pow(max(0.0, 1.0 - abs(dot(n, v))), 6.0);
            col = 0.42 + 0.58 * col;
        } else if (vm < 2.5) {  // the seam: the shadow in the gap
            col = float3(0.16);
            if (u.ex > 0.0) col = mix(col, float3(0.70 + 0.18 * ss(-0.6, 0.7, r.y)), ss(0.0, 0.12, u.ex));  // apart: the shell rim is plain steel
        } else if (vm < 3.5) {  // the front parts
            float3 t = tf.sample(sm, in.vuv).rgb;
            float id = tf.sample(sn, in.vuv, level(0)).a;  // the material id, not blended
            // The screen module's LCD (part 4, only apart) is the picture itself: no parallax.
            float2 pu = pt > 3.5 && pt < 4.5 ? in.vuv : lcdUV(n, in.vp, M, in.vuv);
            float3 pic = tf.sample(sm, pu).rgb;
            col = frontPart(n, in.vp, in.vo, M, in.vuv, pt, t, id, pu, pic, u.blk, u.ex, gu, go);
            if (u.flat > 0.0) {
                // CLA-119, the mock's 2D layer (k3d_src3.js `t2`, `u2d` 1): the 2D device's picture
                // plus only the change of the 3D light from the rest pose, so at 0° the front is
                // the 2D device. `rest` is the same point lit as it rests: face on, 2600 pt away.
                float3 on = ff ? normalize(in.von) : -normalize(in.von);
                float3 vr = in.vo + float3(0.0, 0.0, -2600.0);  // K3DRenderer.distance
                float3x3 I = float3x3(1.0);
                float3 rest = frontPart(on, vr, in.vo, I, in.vuv, pt, t, id, pu, pic, u.blk, u.ex, gu, go);
                // In the LCD the picture moves with the parallax, from where it is at rest.
                float isL = isId(id, 251.0) * (1.0 - step(0.5, in.vuv.y));
                float2 ru = restUV(in.vo);
                float2 fu = mix(ru, ru + pu - lcdUV(on, vr, I, in.vuv), isL);
                float4 f2 = flatAt(t2, sf, fu, ru);
                float2 pin = fu * float2(732.0, 1226.0);  // past the picture's edge: the dark inner wall
                if (isL > 0.5 && (pin.x < 66.0 || pin.x > 666.0 || pin.y < 65.0 || pin.y > 515.0)) f2 = float4(0.10, 0.10, 0.11, f2.a);
                // The plate's round and the wheel's side take the 3D light only (the mock), except
                // within `restAngle` of rest, where all of the body that shows is the 2D picture.
                f2.a *= max(ss(0.25, 0.7, on.z), nearRest) * u.flat;
                col = saturate(mix(col, f2.rgb + (col - rest), f2.a));
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
        // CLA-119: near rest, the hole walls, the window's cut edge, the steel and the seam that
        // show round the front are the 2D picture too, so at 0° the body is the 2D device.
        if (u.flat > 0.0 && ff && (vm < 2.5 || (vm > 9.5 && vm < 10.5)) && nearRest > 0.0) {
            float2 ru = restUV(in.vo);
            float4 f2 = flatAt(t2, sf, ru, ru);
            col = mix(col, f2.rgb, f2.a * nearRest * u.flat);
        }
        // Apart, seen from behind, the front parts show their back faces: plain material, no
        // print, in the same physical light. The shell's back faces are not drawn.
        if (!ff && vm < 10.5) {
            if (pt < 0.5) discard_fragment();
            float g = pow(clamp(physE(n, in.vp, in.vo, M), 0.0, 2.0), 0.4545);
            if (pt < 1.5) col = uTint * 0.72 * g * (u.blk > 0.5 ? 0.34 : 1.0);  // plate: bare aluminium
            else if (pt < 2.5) col = mix(float3(0.10, 0.11, 0.12) * (0.6 + 0.4 * g), float3(0.78, 0.82, 0.86) * (0.5 + 0.4 * fr) + 0.12 * env(r), glass);  // window
            else if (pt < 3.5) col = (u.blk > 0.5 ? float3(0.13) : float3(0.90, 0.91, 0.92)) * g;  // wheel: plain plastic
            else if (pt < 4.5) col = float3(0.12, 0.14, 0.13) * (0.5 + 0.5 * g);  // screen module: dark board
            else col = uTint * pow(0.50, 0.4545) * g * (u.blk > 0.5 ? 0.34 : 1.0);  // center button
        }
        return float4(col, oA);
    }
    """
}
