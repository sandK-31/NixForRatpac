"""Open a real (non-batch) ROOT canvas, draw a fitted Gaussian, save it.

--hold N        keep the window up N seconds, then close it
--wait-close    keep it up until the user closes the window (max 10 min)

Prints "ROOT_GUI backend=..." and exits non-zero if ROOT fell back to batch
mode, i.e. found no display to draw on.
"""
import argparse
import sys
import time

import ROOT

p = argparse.ArgumentParser()
p.add_argument("png")
p.add_argument("--hold", type=float, default=3)
p.add_argument("--wait-close", action="store_true")
args = p.parse_args()

ROOT.gROOT.SetBatch(False)
# ROOT loads its graphics backend (TGQuartz, TGX11) when the first canvas
# opens; gVirtualX is the do-nothing TVirtualX base until then.
c = ROOT.TCanvas("nfr", "NixForRatpac test: ROOT canvas", 700, 500)
backend = ROOT.gVirtualX.ClassName()
imp = c.GetCanvasImp().ClassName() if c.GetCanvasImp() else "none"
print(f"ROOT_GUI batch={bool(ROOT.gROOT.IsBatch())} backend={backend} window={imp}")
if ROOT.gROOT.IsBatch() or backend == "TVirtualX" or imp in ("none", "TCanvasImp"):
    sys.exit("ROOT has no graphics backend here (batch mode)")

h = ROOT.TH1F("h", "NixForRatpac test: 20000 Gaussian samples", 100, -4, 4)
h.FillRandom("gaus", 20000)
h.Fit("gaus", "Q")
h.Draw()
c.Update()
ROOT.gSystem.ProcessEvents()
c.SaveAs(args.png)

deadline = time.time() + (600 if args.wait_close else args.hold)
while time.time() < deadline:
    if args.wait_close and not ROOT.gROOT.GetListOfCanvases().FindObject("nfr"):
        break
    ROOT.gSystem.ProcessEvents()
    time.sleep(0.05)
print(f"ROOT_GUI ok window={c.GetWw()}x{c.GetWh()}" if not args.wait_close
      else "ROOT_GUI ok, closed")
