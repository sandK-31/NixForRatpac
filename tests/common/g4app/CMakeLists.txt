# Standalone Geant4 application: needs only the `.#geant4` shell.
cmake_minimum_required(VERSION 3.16)
project(nfr_g4app CXX)
set(CMAKE_CXX_STANDARD 17)
find_package(Geant4 REQUIRED ui_all vis_all)
# The vis test talks to Qt directly (timer, screenshot).
find_package(Qt6 REQUIRED COMPONENTS Widgets)
add_executable(g4app g4app.cc)
target_link_libraries(g4app PRIVATE ${Geant4_LIBRARIES} Qt6::Widgets)
