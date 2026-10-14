// Minimal Geant4 application for the NixForRatpac test suite.
//
//   g4app batch <events>
//       100 MeV electrons into a 1 m water cube, FTFP_BERT physics (so the
//       datasets get used). Prints "BATCH ..." with the mean energy deposit.
//
//   g4app vis <driver|default> <viewer.png> <window.png>
//       Opens the Qt GUI, draws the geometry and three showers, then (from a
//       timer inside the running Qt event loop) screenshots the viewer and
//       the whole window, checks the viewer is not blank, and quits. Prints
//       "VIEWER ..." and exits 0 only if the picture has geometry and tracks.

#include <FTFP_BERT.hh>
#include <G4Box.hh>
#include <G4Event.hh>
#include <G4LogicalVolume.hh>
#include <G4NistManager.hh>
#include <G4PVPlacement.hh>
#include <G4ParticleGun.hh>
#include <G4ParticleTable.hh>
#include <G4RunManagerFactory.hh>
#include <G4Step.hh>
#include <G4SystemOfUnits.hh>
#include <G4UIExecutive.hh>
#include <G4UIQt.hh>
#include <G4UImanager.hh>
#include <G4UserEventAction.hh>
#include <G4UserSteppingAction.hh>
#include <G4VGraphicsSystem.hh>
#include <G4VUserActionInitialization.hh>
#include <G4VUserDetectorConstruction.hh>
#include <G4VUserPrimaryGeneratorAction.hh>
#include <G4VisExecutive.hh>

#include <QCoreApplication>
#include <QImage>
#include <QMainWindow>
#include <QTabWidget>
#include <QTimer>

#include <cstdio>
#include <cstdlib>
#include <map>
#include <string>

namespace {

G4LogicalVolume* gWater = nullptr;
double gEdep = 0;     // this event
double gEdepSum = 0;  // all events
int gEvents = 0;

class Detector : public G4VUserDetectorConstruction {
 public:
  G4VPhysicalVolume* Construct() override {
    auto* nist = G4NistManager::Instance();
    auto* world = new G4LogicalVolume(new G4Box("World", 1 * m, 1 * m, 1 * m),
                                      nist->FindOrBuildMaterial("G4_AIR"), "World");
    gWater = new G4LogicalVolume(new G4Box("Water", 0.5 * m, 0.5 * m, 0.5 * m),
                                 nist->FindOrBuildMaterial("G4_WATER"), "Water");
    new G4PVPlacement(nullptr, {}, gWater, "Water", world, false, 0);
    return new G4PVPlacement(nullptr, {}, world, "World", nullptr, false, 0);
  }
};

class Gun : public G4VUserPrimaryGeneratorAction {
 public:
  Gun() : fGun(1) {
    fGun.SetParticleDefinition(G4ParticleTable::GetParticleTable()->FindParticle("e-"));
    fGun.SetParticleEnergy(100 * MeV);
    fGun.SetParticlePosition({0, 0, -0.9 * m});
    fGun.SetParticleMomentumDirection({0, 0, 1});
  }
  void GeneratePrimaries(G4Event* event) override { fGun.GeneratePrimaryVertex(event); }

 private:
  G4ParticleGun fGun;
};

class Stepping : public G4UserSteppingAction {
 public:
  void UserSteppingAction(const G4Step* step) override {
    if (step->GetPreStepPoint()->GetPhysicalVolume()->GetLogicalVolume() == gWater)
      gEdep += step->GetTotalEnergyDeposit();
  }
};

class Events : public G4UserEventAction {
 public:
  void BeginOfEventAction(const G4Event*) override { gEdep = 0; }
  void EndOfEventAction(const G4Event*) override {
    gEdepSum += gEdep;
    ++gEvents;
  }
};

class Actions : public G4VUserActionInitialization {
 public:
  void Build() const override {
    SetUserAction(new Gun);
    SetUserAction(new Stepping);
    SetUserAction(new Events);
  }
};

G4RunManager* MakeRunManager() {
  auto* rm = G4RunManagerFactory::CreateRunManager(G4RunManagerType::Serial);
  rm->SetUserInitialization(new Detector);
  rm->SetUserInitialization(new FTFP_BERT(0));
  rm->SetUserInitialization(new Actions);
  rm->Initialize();
  return rm;
}

int RunBatch(int events) {
  G4RunManager* rm = MakeRunManager();
  rm->BeamOn(events);
  double mean = gEvents ? gEdepSum / gEvents / MeV : 0;
  std::printf("BATCH %d events, mean deposit %.1f MeV of 100 in the water\n", gEvents, mean);
  delete rm;
  return (gEvents == events && mean > 1 && mean <= 100) ? 0 : 1;
}

// The most common colour is the background; the rest must be a real share of
// the picture. Pure-ish red/green pixels are the default trajectory colours
// (negative = red, neutral = green), i.e. the showers.
struct Stats {
  int colours = 0;
  double nonBackground = 0;
  long trackPixels = 0;
};

Stats Analyse(const QImage& raw) {
  QImage img = raw.convertToFormat(QImage::Format_RGB32);
  std::map<QRgb, long> counts;
  Stats s;
  for (int y = 0; y < img.height(); ++y) {
    auto* line = reinterpret_cast<const QRgb*>(img.constScanLine(y));
    for (int x = 0; x < img.width(); ++x) {
      QRgb c = line[x];
      ++counts[c & 0xffffff];
      int r = qRed(c), g = qGreen(c), b = qBlue(c);
      if ((r > 150 && g < 90 && b < 90) || (g > 150 && r < 90 && b < 90)) ++s.trackPixels;
    }
  }
  long total = static_cast<long>(img.width()) * img.height(), most = 0;
  for (const auto& kv : counts) most = std::max(most, kv.second);
  s.colours = static_cast<int>(counts.size());
  s.nonBackground = total ? 1.0 - static_cast<double>(most) / total : 0;
  return s;
}

int RunVis(int argc, char** argv, const std::string& driver, const char* viewerPng,
           const char* windowPng) {
  auto* ui = new G4UIExecutive(argc, argv, "qt");
  if (!ui->IsGUI()) {
    std::puts("VIEWER no Qt session: G4UIExecutive fell back to a terminal session");
    return 1;
  }
  G4RunManager* rm = MakeRunManager();
  auto* vis = new G4VisExecutive("warnings");
  vis->Initialize();

  G4UImanager* UI = G4UImanager::GetUIpointer();
  std::string failed;
  auto run = [&](const std::string& cmd) {
    if (UI->ApplyCommand(cmd) != 0) failed += " '" + cmd + "'";
  };
  run(driver == "default" ? "/vis/open" : "/vis/open " + driver);
  run("/vis/viewer/set/autoRefresh false");
  run("/vis/drawVolume");
  run("/vis/viewer/set/viewpointThetaPhi 70 20 deg");
  run("/vis/scene/add/trajectories smooth");
  run("/vis/scene/endOfEventAction accumulate");
  run("/vis/viewer/set/autoRefresh true");
  run("/run/beamOn 3");

  G4VGraphicsSystem* gs = vis->GetCurrentGraphicsSystem();
  std::string used = gs ? gs->GetNickname() : "none";
  auto* qt = dynamic_cast<G4UIQt*>(UI->GetG4UIWindow());

  int rc = 1;
  // Fires once the event loop has been running long enough to show and
  // paint the window.
  QTimer::singleShot(5000, [&] {
    QWidget* viewer = qt && qt->GetViewerTabWidget() ? qt->GetViewerTabWidget()->currentWidget()
                                                     : nullptr;
    if (!viewer) {
      std::printf("VIEWER driver=%s: no viewer widget in the Qt window%s%s\n", used.c_str(),
                  failed.empty() ? "" : "; failed commands:", failed.c_str());
    } else {
      QImage shot = viewer->grab().toImage();
      shot.save(viewerPng);
      qt->GetMainWindow()->grab().toImage().save(windowPng);
      Stats s = Analyse(shot);
      bool ok = failed.empty() && s.nonBackground > 0.002 && s.colours >= 3 && s.trackPixels > 20;
      std::printf("VIEWER driver=%s %dx%d window_visible=%d colours=%d non_background=%.2f%% "
                  "track_pixels=%ld%s%s\n",
                  used.c_str(), shot.width(), shot.height(),
                  int(qt->GetMainWindow()->isVisible()), s.colours, 100 * s.nonBackground,
                  s.trackPixels, failed.empty() ? "" : " failed:", failed.c_str());
      rc = ok ? 0 : 1;
    }
    std::fflush(stdout);
    QCoreApplication::quit();
  });
  ui->SessionStart();

  delete ui;
  delete vis;
  delete rm;
  return rc;
}

}  // namespace

int main(int argc, char** argv) {
  std::string mode = argc > 1 ? argv[1] : "";
  if (mode == "batch" && argc == 3) return RunBatch(std::atoi(argv[2]));
  if (mode == "vis" && argc == 5) {
    // G4UIExecutive takes argc/argv for Qt; hand it just the program name.
    int qtArgc = 1;
    return RunVis(qtArgc, argv, argv[2], argv[3], argv[4]);
  }
  std::fprintf(stderr,
               "usage: g4app batch <events>\n"
               "       g4app vis <driver|default> <viewer.png> <window.png>\n");
  return 2;
}
