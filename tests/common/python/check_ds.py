"""Read a full RAT::DS file (outroot) through RAT's own Python module.

This exercises RAT's ROOT dictionary: cling has to parse the RAT::DS headers,
which fails if ROOT_INCLUDE_PATH is missing include/stlplus. Prints one
"DS ..." line.
"""
import argparse
import collections
import sys

import rat  # $RATSHARE/python/rat

p = argparse.ArgumentParser()
p.add_argument("file")
p.add_argument("--events", type=int, required=True)
p.add_argument("--pdg", type=int, required=True, help="expected primary PDG code")
args = p.parse_args()

reader = rat.RAT.DSReader(args.file)
n = reader.GetEntryCount()
pe = 0
pdgs = collections.Counter()
for i in range(n):
    mc = reader.GetEntry(i).GetMC()
    pe += mc.GetNumPE()
    pdgs[mc.GetMCParticle(0).GetPDGCode()] += 1

print(f"DS events={n} mean_numPE={pe / max(n, 1):.1f} primary_pdgs={dict(pdgs)}")
if n != args.events or pdgs.get(args.pdg, 0) != n:
    sys.exit(1)
