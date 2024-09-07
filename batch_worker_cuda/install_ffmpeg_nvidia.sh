#!/bin/bash

git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
cd nv-codec-headers && make install && cd

apt install -y build-essential yasm cmake libtool libc6 libc6-dev unzip \
libnuma1 libnuma-dev cuda-nvcc-12-5 nvidia-cuda-toolkit libavdevice60 yasm \
libnvidia-decode-550 libnvidia-encode-550

git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg/

apt install -y libx264-dev libx265-dev
export PATH=$PATH:/usr/local/cuda-12.5/bin

cd ffmpeg/
./configure --enable-gpl --enable-libx264 ---enable-libx265 --enable-libx264 -enable-nonfree --enable-cuda-nvcc --enable-libnpp --extra-cflags=-I/usr/local/cuda/include --extra-ldflags=-L/usr/local/cuda/lib64 --disable-static --enable-shared
make -j 8 && make install && cd
