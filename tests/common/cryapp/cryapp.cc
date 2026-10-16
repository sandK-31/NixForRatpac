// CRY on its own, no RAT-PAC: compiled against $CRYINCLUDE/$CRYLIB, data from
// $CRYDATA. Generates N sea-level showers and counts the particles.
#include <CRYGenerator.h>
#include <CRYParticle.h>
#include <CRYSetup.h>
#include <CRYUtils.h>

#include <cstdio>
#include <cstdlib>
#include <map>
#include <string>
#include <vector>

int main(int argc, char** argv) {
  const char* data = std::getenv("CRYDATA");
  if (!data) {
    std::puts("CRYDATA is not set");
    return 1;
  }
  int n = argc > 1 ? std::atoi(argv[1]) : 300;
  CRYSetup setup(
      "returnMuons 1 returnNeutrons 1 returnProtons 1 returnGammas 1 "
      "returnElectrons 1 returnPions 1 altitude 0 latitude 37.9 "
      "date 10-14-2026 subboxLength 3",
      data);
  CRYGenerator gen(&setup);

  std::map<std::string, int> counts;
  std::vector<CRYParticle*> ev;
  for (int i = 0; i < n; ++i) {
    ev.clear();
    gen.genEvent(&ev);
    for (CRYParticle* p : ev) {
      ++counts[CRYUtils::partName(p->id())];
      delete p;
    }
  }
  std::printf("CRYAPP %d showers (%.2f s of sky):", n, gen.timeSimulated());
  for (const auto& [name, count] : counts) std::printf(" %s:%d", name.c_str(), count);
  std::printf("\n");
  return counts["muon"] > 0 ? 0 : 1;
}
