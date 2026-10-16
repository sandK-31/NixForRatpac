// Links libRATPAC and touches what downstream code always needs: RATDB
// (reading a table from $RATSHARE) and the DS classes.
#include <RAT/DB.hh>
#include <RAT/DS/Root.hh>

#include <cstdlib>
#include <iostream>
#include <string>

int main() {
  const char* share = std::getenv("RATSHARE");
  if (!share) {
    std::cerr << "RATSHARE is not set\n";
    return 1;
  }
  RAT::DB* db = RAT::DB::Get();
  db->Load(std::string(share) + "/ratdb/CRY.ratdb");
  int subbox = db->GetLink("CRY")->GetI("subboxLength");

  RAT::DS::Root ds;
  RAT::DS::MC* mc = ds.GetMC();

  std::cout << "RATAPP RATDB CRY.subboxLength=" << subbox
            << ", DS::Root MC particles=" << mc->GetMCParticleCount() << "\n";
  return subbox == 10 ? 0 : 1;
}
