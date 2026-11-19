"""Spread the roster sheet's team ratings so teams feel different.

Reads data/knockout_hockey_rosters_base.csv (the hand-made sheet, untouched) and writes
data/knockout_hockey_rosters.csv, which the game reads. Two passes per team:

1. Style: the team's signature stat goes up, its weak spot goes down (STYLES).
2. Strength: every player on the team moves by the same amount until the team's overall
   hits its target (ORDER / TARGETS). Gaps between teammates are kept.

Team overall = 40% top-6 forwards' overall + 30% top-4 defense + 30% starting goalie
(goalie less 8, since the sheet's goalies center on 83 and skaters on 75). The targets
average out to the old league average, so gameplay tuning (Rosters centers) holds.

Edit the tables and rerun:  python tools/spread_ratings.py   (add --report to only print)
"""
import csv
import io
import statistics as st
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = ROOT / "data" / "knockout_hockey_rosters_base.csv"
OUT = ROOT / "data" / "knockout_hockey_rosters.csv"

SKATER = ["SKA", "SHT", "PAS", "HND", "PHY", "DEF"]
GOALIE = ["REF", "POS", "GLV", "BLK", "RBD"]

# Team order in each conference, best first. The first three are the unlockables.
ORDER = {
    "East": ["NBW", "PBC", "CST",  # Whalers, Campers, Sweet Tea
             "BUR", "MEL", "NHG", "MYS", "ADK", "QCP", "RIQ", "PHI", "CCC", "NYR"],
    "Central": ["MIN", "LUC", "FLA",  # Geese, Luchadores, Florida Man
                "LSG", "CHI", "MIM", "KYM", "MBJ", "NSH", "WIS", "TXA", "OKE", "NDK"],
    "West": ["ROS", "HOL", "BAJ",  # Grays, Stuntmen, Chupacabras
             "POR", "ANC", "SEA", "RMG", "MON", "YEL", "MOJ", "XOC", "TAC", "BOI"],
}
# Team overall by place in the conference.
TARGETS = [86, 84, 82, 80, 78.5, 77, 75.5, 74, 72.5, 71, 69.5, 68, 66]

# Style: skater stat changes, plus "G" for the starting goalie's stats.
STYLES = {
    "Speed": {"SKA": 6, "PHY": -4},
    "Snipers": {"SHT": 6, "DEF": -4},
    "Playmakers": {"PAS": 6, "HND": 6, "PHY": -4},
    "Lockdown": {"DEF": 6, "SHT": -4},
    "Bruisers": {"PHY": 6, "SKA": -4},
    "Hot Goalie": {"G": 6, "SHT": -2, "PAS": -2, "HND": -2},
}
TEAM_STYLE = {
    # East
    "NBW": "Bruisers", "PBC": "Bruisers", "CST": "Playmakers", "BUR": "Speed",
    "MEL": "Lockdown", "NHG": "Hot Goalie", "MYS": "Playmakers", "ADK": "Speed",
    "QCP": "Snipers", "RIQ": "Lockdown", "PHI": "Bruisers", "CCC": "Speed", "NYR": "Bruisers",
    # Central
    "MIN": "Speed", "LUC": "Bruisers", "FLA": "Snipers", "LSG": "Snipers",
    "CHI": "Bruisers", "MIM": "Hot Goalie", "KYM": "Snipers", "MBJ": "Bruisers",
    "NSH": "Playmakers", "WIS": "Lockdown", "TXA": "Lockdown", "OKE": "Lockdown", "NDK": "Speed",
    # West
    "ROS": "Hot Goalie", "HOL": "Bruisers", "BAJ": "Speed", "POR": "Bruisers",
    "ANC": "Lockdown", "SEA": "Snipers", "RMG": "Bruisers", "MON": "Playmakers",
    "YEL": "Snipers", "MOJ": "Lockdown", "XOC": "Playmakers", "TAC": "Playmakers", "BOI": "Lockdown",
}


def clamp(v: float) -> int:
    return max(40, min(99, round(v)))


def is_goalie(p: dict) -> bool:
    return p["position"] == "G"


def keys(p: dict) -> list:
    return GOALIE if is_goalie(p) else SKATER


def team_ovr(ps: list) -> float:
    F = sorted([p for p in ps if p["position"] in ("C", "LW", "RW")], key=lambda p: -p["overall"])
    D = sorted([p for p in ps if p["position"] == "D"], key=lambda p: -p["overall"])
    G = max((p for p in ps if is_goalie(p)), key=lambda p: p["overall"])
    return (0.4 * st.mean(p["overall"] for p in F[:6]) + 0.3 * st.mean(p["overall"] for p in D[:4])
            + 0.3 * (G["overall"] - 8))


def styled(ps: list, style: dict) -> list:
    """Float ratings with the style applied (overall moves by the mean change)."""
    out = []
    starter = max((p for p in ps if is_goalie(p)), key=lambda p: int(p["overall"]))
    for p in ps:
        q = {k: float(p[k]) for k in keys(p)}
        if is_goalie(p):
            d = {k: style.get("G", 0) for k in GOALIE} if p is starter else {}
        else:
            d = {k: v for k, v in style.items() if k != "G"}
        for k, v in d.items():
            q[k] += v
        q["overall"] = float(p["overall"]) + sum(d.values()) / len(keys(p))
        out.append(q)
    return out


def shifted(base: list, ps: list, s: float) -> list:
    return [dict(p, overall=clamp(b["overall"] + s), **{k: clamp(b[k] + s) for k in keys(p)})
            for p, b in zip(ps, base)]


def main() -> None:
    src = BASE.read_text(encoding="utf-8")
    rows = list(csv.DictReader(io.StringIO(src)))
    header = list(rows[0].keys())
    by_team = {}
    for r in rows:
        by_team.setdefault(r["abbr"], []).append(r)
    listed = [a for c in ORDER.values() for a in c]
    assert sorted(listed) == sorted(by_team), "ORDER must list every team once"
    assert sorted(TEAM_STYLE) == sorted(by_team), "TEAM_STYLE must cover every team"

    report = []
    for conf, abbrs in ORDER.items():
        for place, abbr in enumerate(abbrs):
            ps = by_team[abbr]
            target = TARGETS[place]
            before = team_ovr([dict(p, overall=int(p["overall"])) for p in ps])
            base = styled(ps, STYLES[TEAM_STYLE[abbr]])
            # Find the shift that lands the team on its target (clamping makes it uneven).
            s = target - team_ovr([dict(p, overall=b["overall"]) for p, b in zip(ps, base)])
            for _ in range(20):
                err = target - team_ovr(shifted(base, ps, s))
                if abs(err) < 0.15:
                    break
                s += err
            new = shifted(base, ps, s)
            for p, n in zip(ps, new):
                p["overall"] = str(n["overall"])
                for k in keys(p):
                    p[k] = str(n[k])
            report.append((conf, place + 1, ps[0]["team"], TEAM_STYLE[abbr], before, team_ovr(new), s))

    cur = None
    for conf, n, team, style, before, after, s in report:
        if conf != cur:
            cur = conf
            print(f"\n{conf}\n {'#':>2} {'Team':26} {'Style':11} {'was':>5} {'now':>5} {'shift':>6}")
        print(f" {n:>2} {team:26} {style:11} {before:5.1f} {after:5.1f} {s:+6.1f}")

    if "--report" in sys.argv:
        return
    buf = io.StringIO()
    w = csv.DictWriter(buf, fieldnames=header, lineterminator="\r\n" if "\r\n" in src else "\n")
    w.writeheader()
    w.writerows(rows)
    OUT.write_text(buf.getvalue(), encoding="utf-8", newline="")
    print(f"\nWrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
