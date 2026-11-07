"""Convert a (binary or ASCII) STL to a decimated, smooth-shaded OBJ that Godot imports.

Decimation is vertex clustering: vertices are snapped to a 3D grid, merged per cell
(averaged), and triangles that collapse are dropped. The grid size is searched so the
result lands near --tris triangles. Good enough for helmets and masks seen from a
broadcast camera; not for hero close-ups.

    python tools/stl_to_obj.py in.stl out.obj --tris 8000 --scale 0.001
"""
import argparse
import math
import struct


def read_stl(path):
    data = open(path, "rb").read()
    tris = []
    if data[:5] == b"solid" and b"facet" in data[:400]:
        verts = []
        for line in data.decode("ascii", "ignore").splitlines():
            parts = line.split()
            if parts and parts[0] == "vertex":
                verts.append(tuple(float(p) for p in parts[1:4]))
                if len(verts) == 3:
                    tris.append(tuple(verts))
                    verts = []
        return tris
    n = struct.unpack("<I", data[80:84])[0]
    off = 84
    for _ in range(n):
        v = struct.unpack("<12f", data[off:off + 48])
        tris.append(((v[3], v[4], v[5]), (v[6], v[7], v[8]), (v[9], v[10], v[11])))
        off += 50
    return tris


def cluster(tris, cell):
    index = {}
    sums = []
    faces = []
    seen = set()
    for t in tris:
        ids = []
        for p in t:
            key = (math.floor(p[0] / cell), math.floor(p[1] / cell), math.floor(p[2] / cell))
            i = index.get(key)
            if i is None:
                i = len(sums)
                index[key] = i
                sums.append([0.0, 0.0, 0.0, 0])
            s = sums[i]
            s[0] += p[0]; s[1] += p[1]; s[2] += p[2]; s[3] += 1
            ids.append(i)
        if ids[0] == ids[1] or ids[1] == ids[2] or ids[0] == ids[2]:
            continue
        key = tuple(sorted(ids))
        if key in seen:
            continue
        seen.add(key)
        faces.append(tuple(ids))
    verts = [(s[0] / s[3], s[1] / s[3], s[2] / s[3]) for s in sums]
    return verts, faces


def normals(verts, faces):
    acc = [[0.0, 0.0, 0.0] for _ in verts]
    for a, b, c in faces:
        pa, pb, pc = verts[a], verts[b], verts[c]
        u = (pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2])
        v = (pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2])
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        for i in (a, b, c):
            acc[i][0] += n[0]; acc[i][1] += n[1]; acc[i][2] += n[2]
    out = []
    for n in acc:
        l = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) or 1.0
        out.append((n[0] / l, n[1] / l, n[2] / l))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--tris", type=int, default=8000)
    ap.add_argument("--scale", type=float, default=1.0)
    a = ap.parse_args()
    tris = read_stl(a.src)
    lo = [min(p[k] for t in tris for p in t) for k in range(3)]
    hi = [max(p[k] for t in tris for p in t) for k in range(3)]
    size = max(hi[k] - lo[k] for k in range(3))
    print("source: %d tris, bounds %s .. %s" % (len(tris), lo, hi))
    # Binary search the grid cell for the target triangle count.
    small, big = size / 2000.0, size / 10.0
    best = None
    for _ in range(14):
        cell = math.sqrt(small * big)
        verts, faces = cluster(tris, cell)
        best = (cell, verts, faces)
        if len(faces) > a.tris:
            small = cell
        else:
            big = cell
        if abs(len(faces) - a.tris) < a.tris * 0.08:
            break
    cell, verts, faces = best
    ns = normals(verts, faces)
    with open(a.dst, "w") as f:
        f.write("# decimated from %s (cell %.4f)\n" % (a.src, cell))
        for v in verts:
            f.write("v %.5f %.5f %.5f\n" % (v[0] * a.scale, v[1] * a.scale, v[2] * a.scale))
        for n in ns:
            f.write("vn %.4f %.4f %.4f\n" % n)
        for x, y, z in faces:
            f.write("f %d//%d %d//%d %d//%d\n" % (x + 1, x + 1, y + 1, y + 1, z + 1, z + 1))
    print("wrote %s: %d verts, %d tris (cell %.3f)" % (a.dst, len(verts), len(faces), cell))


if __name__ == "__main__":
    main()
