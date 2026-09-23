#!/usr/bin/env python3
"""Downloads Voyager 1 ephemerides (JPL Horizons) and the HYG star catalogue and
packs them into the compact binary resources the app loads at runtime.

  Resources/ephemeris.bin  Voyager 1 state vectors in several segments (finest wins):
                             launch (5 min, 1 h), Jupiter & Saturn encounters (10 min),
                             daily 1977-09-25 … 2100-01-01. Heliocentric + geocentric, ICRF.
  Resources/bodies.bin     Voyager → body vectors for the Moon, Jupiter + Galilean moons,
                           Saturn + major moons around the encounters.
  Resources/stars.bin      stars brighter than mag 8 plus every star within 25 pc,
                           with 3D position and space velocity for deep-time mode.
"""
import csv, json, os, struct, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
RES = os.path.join(ROOT, "Resources")
API = "https://ssd.jpl.nasa.gov/api/horizons.api"
HYG = "https://raw.githubusercontent.com/astronexus/HYG-Database/main/hyg/CURRENT/hygdata_v41.csv"


def horizons(target, center, start, stop, step):
    name = f"{target}_{center}_{start}_{stop}_{step}".replace(" ", "").replace(":", "").replace("@", "at")
    path = os.path.join(DATA, name + ".txt")
    if not os.path.exists(path):
        q = {
            "format": "text", "COMMAND": f"'{target}'", "OBJ_DATA": "NO", "MAKE_EPHEM": "YES",
            "EPHEM_TYPE": "VECTORS", "CENTER": f"'{center}'", "REF_PLANE": "FRAME", "REF_SYSTEM": "ICRF",
            "VEC_TABLE": "2", "VEC_CORR": "NONE", "OUT_UNITS": "KM-S", "CSV_FORMAT": "YES",
            "START_TIME": f"'{start}'", "STOP_TIME": f"'{stop}'", "STEP_SIZE": f"'{step}'",
        }
        url = API + "?" + urllib.parse.urlencode(q, quote_via=urllib.parse.quote)
        print("horizons", target, center, start, stop, step)
        urllib.request.urlretrieve(url, path)
    rows, on = [], False
    for line in open(path):
        if line.startswith("$$SOE"):
            on = True
        elif line.startswith("$$EOE"):
            break
        elif on:
            p = [x.strip() for x in line.split(",")]
            rows.append((float(p[0]),) + tuple(float(x) for x in p[2:8]))
    if not rows:
        raise SystemExit(f"no data in {path}")
    return rows


def voyager_segment(start, stop, step):
    helio = horizons("-31", "500@10", start, stop, step)
    geo = horizons("-31", "500@399", start, stop, step)
    assert len(helio) == len(geo) and all(a[0] == b[0] for a, b in zip(helio, geo))
    return helio, geo


def write_segment(f, rows_a, rows_b=None):
    jd0 = rows_a[0][0]
    step = rows_a[1][0] - rows_a[0][0]
    f.write(struct.pack("<ddI", jd0, step, len(rows_a)))
    for i, a in enumerate(rows_a):
        vals = a[1:] + (rows_b[i][1:] if rows_b else ())
        f.write(struct.pack(f"<{len(vals)}d", *vals))


def main():
    os.makedirs(DATA, exist_ok=True)

    # --- Voyager 1 --------------------------------------------------------
    segments = [
        voyager_segment("1977-09-05 14:00", "1977-09-07 00:00", "5 m"),
        voyager_segment("1977-09-07 00:00", "1977-09-26 00:00", "1 h"),
        voyager_segment("1979-02-25 00:00", "1979-03-15 00:00", "10 m"),
        voyager_segment("1980-11-05 00:00", "1980-11-20 00:00", "10 m"),
    ]
    daily_h, daily_g = [], []
    for a, b in [("1977-09-25", "2008-01-01"), ("2008-01-01", "2038-01-01"),
                 ("2038-01-01", "2068-01-01"), ("2068-01-01", "2100-01-01")]:
        h, g = voyager_segment(a, b, "1 d")
        if daily_h and daily_h[-1][0] == h[0][0]:
            h, g = h[1:], g[1:]
        daily_h += h
        daily_g += g
    segments.append((daily_h, daily_g))
    with open(os.path.join(RES, "ephemeris.bin"), "wb") as f:
        f.write(b"VGR2")
        f.write(struct.pack("<I", len(segments)))
        for h, g in segments:
            write_segment(f, h, g)
    print("ephemeris segments:", [len(h) for h, _ in segments])

    # --- Bodies seen up close ---------------------------------------------
    jupiter = (["599", "501", "502", "503", "504"],
               [("1978-12-01", "1979-07-01", "6 h"), ("1979-02-25", "1979-03-15", "10 m")])
    saturn = (["699", "606", "605", "604", "603", "602", "601"],
              [("1980-08-15", "1981-02-15", "6 h"), ("1980-11-05", "1980-11-20", "10 m")])
    moon = (["301"], [("1977-09-05 14:00", "1977-10-20 00:00", "1 h")])
    bodies = []
    for ids, windows in (moon, jupiter, saturn):
        for naif in ids:
            segs = [horizons(naif, "500@-31", a, b, s) for a, b, s in windows]
            bodies.append((int(naif), segs))
    with open(os.path.join(RES, "bodies.bin"), "wb") as f:
        f.write(b"BOD1")
        f.write(struct.pack("<I", len(bodies)))
        for naif, segs in bodies:
            f.write(struct.pack("<iI", naif, len(segs)))
            for rows in segs:
                write_segment(f, rows)
    print("bodies:", [(n, [len(s) for s in segs]) for n, segs in bodies])

    # --- Stars ------------------------------------------------------------
    hyg = os.path.join(DATA, "hyg.csv")
    if not os.path.exists(hyg):
        print("downloading HYG")
        urllib.request.urlretrieve(HYG, hyg)
    stars = []
    with open(hyg) as f:
        for s in csv.DictReader(f):
            if s["id"] == "0":
                continue
            mag, dist = float(s["mag"]), float(s["dist"])
            known = 0 < dist < 100000
            if mag > 8.0 and not (known and dist < 25):
                continue
            ci = float(s["ci"]) if s["ci"] else 0.6
            if known:
                xyz = (float(s["x"]), float(s["y"]), float(s["z"]))
                vel = (float(s["vx"]), float(s["vy"]), float(s["vz"]))
                absmag = float(s["absmag"])
            else:
                xyz, vel, absmag = (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), 99.0
            name = s["proper"] or (("Gliese " + s["gl"].replace("Gl ", "").replace("GJ ", "")) if s["gl"] else "") \
                or (s["bayer"] + " " + s["con"] if s["bayer"] else "") or (("HIP " + s["hip"]) if s["hip"] else "")
            stars.append(((float(s["rarad"]), float(s["decrad"]), mag, ci) + xyz + vel + (absmag,), name, known and dist < 25))
    stars.sort(key=lambda s: s[0][2])
    names = {str(i): n for i, (_, n, near) in enumerate(stars) if near and n}
    with open(os.path.join(RES, "star_names.json"), "w") as f:
        json.dump(names, f, separators=(",", ":"))
    stars = [s for s, _, _ in stars]
    with open(os.path.join(RES, "stars.bin"), "wb") as f:
        f.write(b"STR2")
        f.write(struct.pack("<I", len(stars)))
        for s in stars:
            f.write(struct.pack("<11f", *s))
    print("stars:", len(stars))


if __name__ == "__main__":
    main()
