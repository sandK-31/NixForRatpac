"""Summarise a RAT ntuple (outntuple): entries, mean PE, first-primary mix.

Prints one "NTUPLE ..." line and exits non-zero if a requirement fails.
PyROOT rather than uproot, because uproot is not in the shell's Python.
"""
import argparse
import collections
import sys

import ROOT

p = argparse.ArgumentParser()
p.add_argument("file")
p.add_argument("--min-entries", type=int, default=1)
p.add_argument("--require-pdg", default="",
               help="comma-separated PDG codes; some event's first primary must be one of them")
args = p.parse_args()

# Bind the file to a name: a temporary TFile is freed before Get() returns.
f = ROOT.TFile.Open(args.file)
if not f or f.IsZombie():
    sys.exit(f"cannot open {args.file}")
t = f.Get("output")
if not t:
    sys.exit(f"no 'output' tree in {args.file}")

n = t.GetEntries()
pe = 0
pdgs = collections.Counter()
for ev in t:
    pe += ev.mcpecount
    # mcpdg is the first primary's code; mcparticlecount says how many there were.
    pdgs[int(ev.mcpdg)] += 1

names = {11: "e-", -11: "e+", 13: "mu-", -13: "mu+", 22: "gamma", 2112: "n",
         2212: "p", 211: "pi+", -211: "pi-"}
mix = " ".join(f"{names.get(k, k)}:{v}" for k, v in pdgs.most_common())
print(f"NTUPLE entries={n} mean_mcpecount={pe / max(n, 1):.1f} first_primaries=[{mix}]")

if n < args.min_entries:
    sys.exit(1)
wanted = {int(x) for x in args.require_pdg.split(",") if x}
if wanted and not wanted & set(pdgs):
    sys.exit(1)
