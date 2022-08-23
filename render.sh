#!/usr/bin/env bash

set -e
set -o pipefail

say() {
 echo "$@" | sed \
   -e "s/\(\(@\(red\|green\|yellow\|blue\|magenta\|cyan\|white\|reset\|b\|u\)\)\+\)[[]\{2\}\(.*\)[]]\{2\}/\1\4@reset/g" \
   -e "s/@red/$(tput setaf 1)/g" \
   -e "s/@green/$(tput setaf 2)/g" \
   -e "s/@yellow/$(tput setaf 3)/g" \
   -e "s/@blue/$(tput setaf 4)/g" \
   -e "s/@magenta/$(tput setaf 5)/g" \
   -e "s/@cyan/$(tput setaf 6)/g" \
   -e "s/@white/$(tput setaf 7)/g" \
   -e "s/@reset/$(tput sgr0)/g" \
   -e "s/@b/$(tput bold)/g" \
   -e "s/@u/$(tput sgr 0 1)/g"
}

INPUT_GPX_FILE=$1

if [ -z "$INPUT_GPX_FILE" ]
  then
    say @red[["This script expects a gpx file path as first input"]]
    exit 1;
fi

say @cyan[["Running R script on $INPUT_GPX_FILE"]]
Rscript 3DMap.R $INPUT_GPX_FILE

say @cyan[["Creating GIF file"]]
ffmpeg -framerate 5 -y -i "Track/%02d.png" output.gif

say @cyan[["Creating mp4 video file"]]
ffmpeg -i output.gif \
  -movflags faststart -pix_fmt yuv420p \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" output.mp4

