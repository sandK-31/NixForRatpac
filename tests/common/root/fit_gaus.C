// Batch ROOT check: cling compiles this, fills and fits a Gaussian, and
// writes a PNG (which needs libASImage). Prints one "FIT ..." line.
void fit_gaus(const char* png) {
  gRandom->SetSeed(4);
  TH1F h("h", "NixForRatpac test: 20000 Gaussian samples", 100, -4, 4);
  h.FillRandom("gaus", 20000);
  h.Fit("gaus", "Q");
  TF1* f = h.GetFunction("gaus");
  double sigma = f->GetParameter(2), mean = f->GetParameter(1);
  TCanvas c("c", "c", 700, 500);
  h.Draw();
  c.SaveAs(png);
  bool ok = std::abs(sigma - 1) < 0.05 && std::abs(mean) < 0.05;
  printf("FIT mean=%.3f sigma=%.3f ok=%d\n", mean, sigma, ok);
}
