/// Metal source, compiled at runtime (`swift build` can't compile .metal resources without Xcode's build system).
/// Shapes are signed-distance functions: crisp at any scale, no textures, one instanced draw for everything.
let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Instance {
    float2 pos;
    float2 size;
    float rot;
    float tilt;
    float alpha;
    uint packed;
};

struct VOut {
    float4 position [[position]];
    float2 local;
    float2 half_size;
    float4 color;
    uint shape [[flat]];
};

vertex VOut confetti_vertex(uint vid [[vertex_id]],
                            uint iid [[instance_id]],
                            const device Instance* instances [[buffer(0)]],
                            constant float2& viewport [[buffer(1)]]) {
    Instance p = instances[iid];
    float2 corner = float2((vid & 1) ? 0.5 : -0.5, (vid & 2) ? 0.5 : -0.5);
    float2 local = corner * (p.size + 2.0);            // 1pt pad each side for antialiasing
    float2 q = float2(local.x * p.tilt, local.y);       // 3D flip = foreshorten along local x
    float c = cos(p.rot), s = sin(p.rot);
    float2 world = p.pos + float2(c * q.x - s * q.y, s * q.x + c * q.y);

    VOut out;
    out.position = float4(world / viewport * 2.0 - 1.0, 0.0, 1.0);
    out.local = local;
    out.half_size = p.size * 0.5;
    float shade = 0.75 + 0.25 * p.tilt;                 // back face darker, face-on brightest
    float3 rgb = float3(p.packed & 255u, (p.packed >> 8) & 255u, (p.packed >> 16) & 255u) / 255.0;
    out.color = float4(rgb * shade * p.alpha, p.alpha); // premultiplied
    out.shape = p.packed >> 24;
    return out;
}

fragment float4 confetti_fragment(VOut in [[stage_in]]) {
    float2 p = in.local;
    float2 h = in.half_size;
    float d;
    if (in.shape == 0u) {                               // rounded rectangle, r = 1pt
        float2 q = abs(p) - h + 1.0;
        d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 1.0;
    } else if (in.shape == 1u) {                        // isosceles triangle, apex up
        float2 n = normalize(float2(2.0 * h.y, h.x));
        float side = dot(float2(abs(p.x), p.y) - float2(h.x, -h.y), n);
        d = max(side, -h.y - p.y);
    } else {                                            // circle
        d = length(p) - h.x;
    }
    float a = saturate(0.5 - d / max(fwidth(d), 1e-4));
    return in.color * a;
}
"""
