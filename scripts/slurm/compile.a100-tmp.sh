#!/bin/bash
#SBATCH --time=00:30:00
#SBATCH --job-name=compile.a100-tmp.sh

# Must compile for the A100 nodes on the A100 nodes for the correct CPU arch
#SBATCH --partition=gpu-a100-tmp
#SBATCH --qos=gpu
#SBATCH --gres=gpu:1

# 12 CPU cores (1/4th of the node) and 1 GPUs worth of memoery < 1/4th of the enode)
#SBATCH --cpus-per-task=12
#SBATCH --mem=80G

# Use A100 specific module environment
module unuse /usr/local/modulefiles/live/eb/all
module unuse /usr/local/modulefiles/live/noeb
module use /usr/local/modulefiles/staging/eb-znver3/all/

# Load modules from the A100 specific environment
module load GCC/11.2.0
module load CUDA/11.4.1
module load CMake/3.21.1-GCCcore-11.2.0

# Set the location of the project root relative to this script
PROJECT_ROOT=../..

# navigate into the root directory.
cd $PROJECT_ROOT

# Make the build directory.
mkdir -p build && cd build

# Configure cmake.
cmake .. -DCMAKE_CUDA_ARCHITECTURES=80 -DCMAKE_BUILD_TYPE=Release -DFLAMEGPU_SEATBELTS=OFF -DFLAMEGPU_SHARE_USAGE_STATISTICS=OFF 

# Compile the code
cmake --build . -j `nproc`

