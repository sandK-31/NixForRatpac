# The way a downstream experiment builds against RAT-PAC: find_package(Ratpac)
# and link the exported target.
cmake_minimum_required(VERSION 3.16)
project(nfr_ratapp CXX)
find_package(Ratpac REQUIRED)
add_executable(ratapp ratapp.cc)
target_link_libraries(ratapp PRIVATE Ratpac::RATPAC)
