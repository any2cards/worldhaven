#!/bin/bash
scriptdir=$(dirname $0)
imgdir="${1:-${scriptdir}/../images/character-ability-cards}"

find "${imgdir}" -type f -name '*.png' \
  ! -name "??-??-back.png" \
  ! -name "??-??-player-reference-*.png" \
  ! -name "??-??-halt-back.png" \
  ! -name "??-??-halt-front.png" \
  ! -name "??-bear-reference.png" \
  ! -name "??-bear-reference-back.png" \
  |parallel --jobs $(($(nproc --all)/2)) --keep-order --bar --progress "${scriptdir}/extract-info-ability-card.sh {}"
