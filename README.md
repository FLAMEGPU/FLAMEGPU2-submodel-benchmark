# FLAME GPU 2 Submodel Benchmark Model

This repository contains performance benchmarking of a [FLAMEGPU/FLAMEGPU2](https://github.com/FLAMEGPU/FLAMEGPU2) implementation of the SugarScape model, used to benchmark the [Submodel](https://docs.flamegpu.com/guide/7-submodels/) feature of FLAME GPU 2.

<!-- @todo - expand this description of the benchmark model -->

<!-- ## Visualisation  -->

<!-- @todo - add the visualisation screenshot -->

<!-- ## Benchmark Results -->

<!-- @todo - add results figures -->

## Requirements

Building FLAME GPU has the following requirements. There are also optional dependencies which are required for some components, such as Documentation or Python bindings.

+ [CMake](https://cmake.org/download/) `>= 3.18`
+ [CUDA](https://developer.nvidia.com/cuda-downloads) `>= 11.0` and a Compute Capability `>= 3.5` NVIDIA GPU.
  + CUDA `>= 10.0` currently works, but support will be removed in a future release.
+ C++17 capable C++ compiler (host), compatible with the installed CUDA version
  + [Microsoft Visual Studio 2019](https://visualstudio.microsoft.com/) (Windows)
  + [make](https://www.gnu.org/software/make/) and [GCC](https://gcc.gnu.org/) `>= 7`
  + Older C++ compilers which support C++14 may currently work, but support will be dropped in a future release.
+ [git](https://git-scm.com/)

Optionally:

+ [cpplint](https://github.com/cpplint/cpplint) for linting code
+ [FLAMEGPU2-visualiser](https://github.com/FLAMEGPU/FLAMEGPU2-visualiser) dependencies
  + [SDL](https://www.libsdl.org/)
  + [GLM](http://glm.g-truc.net/) *(consistent C++/GLSL vector maths functionality)*
  + [GLEW](http://glew.sourceforge.net/) *(GL extension loader)*
  + [FreeType](http://www.freetype.org/)  *(font loading)*
  + [DevIL](http://openil.sourceforge.net/)  *(image loading)*
  + [Fontconfig](https://www.fontconfig.org/)  *(Linux only, font detection)*

For the plotting script, Python >= 3.6 is required, with python module dependencies listed in `requirements.txt`.

## Building with CMake

Building via CMake is a three step process, with slight differences depending on your platform.

1. Create a build directory for an out-of tree build
2. Configure CMake into the build directory
    + Using the CMake GUI or CLI tools
    + Specifying build options such as the CUDA Compute Capabilities to target, the inclusion of Visualisation or Python components, or performance impacting features such as `SEATBELTS`.
3. Build compilation targets using the configured build system

### Linux

To configure and build the `submodel_benchmark` binary on linux for benchmarking using Volta generation (SM 70) GPU(s), configure as a Release build with SEATBELTS disabled via :

```bash
# Create the build directory and change into it
mkdir -p build && cd build

# Configure CMake from the command line passing configure-time options. 
cmake .. -DCMAKE_BUILD_TYPE=Release -DSEATBELTS=OFF -DCUDA_ARCH=70 

# Build the target(s)
cmake --build . --target submodel_benchmark -j 8
```

Alternatively to configure for visualisation purposes, enable the `VISUALISATION` CMake option:

```bash
# Create the build directory and change into it
mkdir -p build && cd build

# Configure CMake from the command line passing configure-time options. 
cmake .. -DCMAKE_BUILD_TYPE=Release -DSEATBELTS=OFF -DCUDA_ARCH=70 -DVISUALISATION=ON

# Build the target(s)
cmake --build . --target submodel_benchmark -j 8
```

### Windows

Under Windows, you must instruct CMake on which Visual Studio and architecture to build for, using the CMake `-A` and `-G` options.
This can be done through the GUI or the CLI.

To configure and build the `submodel_benchmark` binary on linux for benchmarking using Volta generation (SM 70) GPU(s), configure as a Release build with SEATBELTS disabled via :

```cmd
REM Create the build directory 
mkdir build
cd build

REM Configure CMake from the command line, specifying the -A and -G options. Alternatively use the GUI
cmake .. -A x64 -G "Visual Studio 16 2019"-DSEATBELTS=OFF -DCUDA_ARCH=70 

REM You can then open Visual Studio manually from the .sln file, or via:
cmake --open . 
REM Alternatively, build from the command line specifying the build configuration
cmake --build . --config Release --target submodel_benchmark --verbose
```

Alternatively to configure for visualisation purposes, enable the `VISUALISATION` CMake option:

```cmd
REM Create the build directory 
mkdir build
cd build

REM Configure CMake from the command line, specifying the -A and -G options. Alternatively use the GUI
cmake .. -A x64 -G "Visual Studio 16 2019"-DSEATBELTS=OFF -DCUDA_ARCH=70 -DVISUALISATION=ON

REM You can then open Visual Studio manually from the .sln file, or via:
cmake --open . 
REM Alternatively, build from the command line specifying the build configuration
cmake --build . --config Release --target submodel_benchmark --verbose
```

## Running the Benchmark or Visualisation


Once compiled, executing the generated binary file will run the performance benchmark, or run the visualisation of a single infinitely running simulation (at a reduced rate of simulation)

I.e. from the `build` directory on Linux:

```bash
./bin/Release/submodel_benchmark 
```

For non-visualisation builds, this will generate a CSV file with performance metrics included which can later be post-processed to generate figures.


## Plotting Benchmark Data

Figures can be generated from data in CSV files via a python script.

It is recommended to use python virtual environment or conda environment for plotting dependencies. 

I.e. for linux to install the dependencies into a virtual environment 