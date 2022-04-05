#!/bin/bash
# Dependencies:
#  - imagemagick (convert): For, interacting with the card images
#  - tesseract-ocr (tesseract): For OCR, reading the characters from the images
#    - Gloomhaven.traineddata model
#  - jq: For json manipulation

# Check for prerequisites
if ! command -v convert >/dev/null; then
  log error "Command convert not found. Please install ImageMagick"
  exit 2
fi
if ! command -v tesseract >/dev/null; then
  log error "Command tesseract not found. Please install tesseract-ocr"
  exit 2
fi

source "$(dirname $0)/extract-utils.sh"

usage() {
  echo "Usage: $0 [options] <ability-card-file>"
  echo
  echo "Extracts information from ability card file"
  echo
  echo "--debug            Output debug information"
  echo "--visualdebug      Open images in feh after tesseracting them"
  echo "--skip-cardno      Skip extracting card number"
  echo "--skip-initiative  Skip extracting initiative"
  echo "--skip-level       Skip extracting level"
}

DEBUG=0
VISUALDEBUG=0
SKIP_LEVEL=0
SKIP_CARDNO=0
SKIP_INITIATIVE=0

# Transform long opts to shorts
for arg in "$@"; do
  shift
  case "$arg" in
    "--debug")           set -- "$@" "-d";;
    "--help")            set -- "$@" "-h";;
    "--skip-cardno")     set -- "$@" "-c";;
    "--skip-initiative") set -- "$@" "-i";;
    "--skip-level")      set -- "$@" "-l";;
    "--visualdebug")     set -- "$@" "-v";;
    *)                   set -- "$@" "$arg"
  esac
done

# Parse opts
OPTIND=1
while getopts "dhcilv" opt
do
  case "$opt" in
    "d") DEBUG=1;;
    "h") >&2 usage; exit;;
    "c") SKIP_CARDNO=1;;
    "i") SKIP_INITIATIVE=1;;
    "l") SKIP_LEVEL=1;;
    "v") VISUALDEBUG=1;;
    *) echo "Unknown option ${OPTARG}"; usage; exit 1 ;;
  esac
done
shift $(expr $OPTIND - 1)

[ "${#}" -ne 1 ] && >&2 usage && exit 1

FILENAME="${1}"
[ ! -r "${FILENAME}" ] && log error "$0: Unable to read file ${FILENAME}" && exit 1

declare -A CARD_LEVEL_POS
CARD_LEVEL_POS=(
  ["images/character-ability-cards/gloomhaven"]="10x21+195+72"
  ["images/character-ability-cards/gloomhaven/BS"]="10x21+195+56"
  ["images/character-ability-cards/gloomhaven/SB"]="12x21+194+72"
  ["images/character-ability-cards/crimson-scales"]="12x21+194+57"
  ["images/character-ability-cards/forgotten-circles"]="10x21+195+56"
  ["images/character-ability-cards/jaws-of-the-lion"]="10x21+195+72"
  ["images/character-ability-cards/frosthaven"]="16x28+24+22"
)
declare -A CARD_LEVEL_FGCOLOR
CARD_LEVEL_FGCOLOR=(
  ["images/character-ability-cards/gloomhaven"]="white"
  ["images/character-ability-cards/gloomhaven/CH"]="black"
  ["images/character-ability-cards/gloomhaven/DS"]="black"
  ["images/character-ability-cards/gloomhaven/NS"]="black"
  ["images/character-ability-cards/gloomhaven/PH"]="black"
  ["images/character-ability-cards/gloomhaven/QM"]="black"
  ["images/character-ability-cards/gloomhaven/SB"]="black"
  ["images/character-ability-cards/gloomhaven/SC"]="black"
  ["images/character-ability-cards/gloomhaven/SK"]="black"
  ["images/character-ability-cards/gloomhaven/TI"]="black"
  ["images/character-ability-cards/crimson-scales"]="white"
  ["images/character-ability-cards/crimson-scales/AA"]="black"
  ["images/character-ability-cards/crimson-scales/HO"]="black"
  ["images/character-ability-cards/crimson-scales/HP"]="black"
  ["images/character-ability-cards/crimson-scales/QA"]="black"
  ["images/character-ability-cards/crimson-scales/RM"]="black"
  ["images/character-ability-cards/forgotten-circles"]="black"
  ["images/character-ability-cards/jaws-of-the-lion"]="black"
  ["images/character-ability-cards/jaws-of-the-lion/RG"]="white"
  ["images/character-ability-cards/frosthaven"]="black"
)
declare -A CARD_LEVEL_ALLOWED_CHARS
CARD_LEVEL_ALLOWED_CHARS=(
  ["images/character-ability-cards"]="1-9X"
  ["images/character-ability-cards/gloomhaven/SB"]="1-9XM"
  ["images/character-ability-cards/crimson-scales/HP"]="1-9XP"
  ["images/character-ability-cards/jaws-of-the-lion"]="1-9XAB"
)
CARD_LEVEL_LENGTH=1

declare -A CARD_INITIATIVE_POS
CARD_INITIATIVE_POS=(
  ["images/character-ability-cards"]="50x47+175+297"
  ["images/character-ability-cards/crimson-scales"]="50x50+175+297"
  ["images/character-ability-cards/frosthaven"]="50x50+175+297"
  ["images/character-ability-cards/frosthaven/BB"]="48x50+150+297;48x50+202+297"
  ["images/character-ability-cards/frosthaven/GE"]="64x50+170+297"
)
declare -A CARD_INITIATIVE_ALLOWED_CHARS
CARD_INITIATIVE_ALLOWED_CHARS=(
  ["images/character-ability-cards"]="0-9"
  ["images/character-ability-cards/crimson-scales/QA"]="0-9X"
)
CARD_INITIATIVE_LENGTH=2

declare -A CARD_NUMBER_POS
CARD_NUMBER_POS=(
  ["images/character-ability-cards/gloomhaven"]="22x16+233+534"
  ["images/character-ability-cards/gloomhaven/BS"]="22x16+237+551"
  ["images/character-ability-cards/crimson-scales"]="22x16+131+552"
  ["images/character-ability-cards/crimson-scales/AA"]="22x16+257+552"
  ["images/character-ability-cards/crimson-scales/QA"]="22x16+257+552"
  ["images/character-ability-cards/crimson-scales/RM"]="22x16+259+552"
  ["images/character-ability-cards/forgotten-circles"]="22x16+237+551"
  ["images/character-ability-cards/jaws-of-the-lion"]="22x16+233+534"
  ["images/character-ability-cards/frosthaven"]="22x16+29+567"
)
CARD_NUMBER_ALLOWED_CHARS="0-9"
CARD_NUMBER_LENGTH=3

# Sort array by key length, apply key if FILENAME starts with the key
# In the end this applies the latest (most exact) value for the matching key
for key in $(printf "%s\n" "${!CARD_LEVEL_POS[@]}" |awk '{print length($0) " " $0}' |sort -n |cut -d' ' -f2-); do
  [ "${FILENAME#$key}" != "${FILENAME}" ] && LEVEL_POS=${CARD_LEVEL_POS[$key]}
done

for key in $(printf "%s\n" "${!CARD_LEVEL_FGCOLOR[@]}" |awk '{print length($0) " " $0}' |sort -n |cut -d' ' -f2-); do
  [ "${FILENAME#$key}" != "${FILENAME}" ] && LEVEL_FGCOLOR=${CARD_LEVEL_FGCOLOR[$key]}
done

for key in $(printf "%s\n" "${!CARD_LEVEL_ALLOWED_CHARS[@]}" |awk '{print length($0) " " $0}' |sort -n |cut -d' ' -f2-);
do
  [ "${FILENAME#$key}" != "${FILENAME}" ] && LEVEL_ALLOWED_CHARS=${CARD_LEVEL_ALLOWED_CHARS[$key]}
done

# Note: Output in array due to frosthaven/BB
for key in $(printf "%s\n" "${!CARD_INITIATIVE_POS[@]}" |awk '{print length($0) " " $0}' |sort -n |cut -d' ' -f2-); do
  [ "${FILENAME#$key}" != "${FILENAME}" ] && IFS=';' read -ra INITIATIVE_POS <<< "${CARD_INITIATIVE_POS[$key]}"
done

for key in $(
  printf "%s\n" "${!CARD_INITIATIVE_ALLOWED_CHARS[@]}" |awk '{print length($0) " " $0}' |sort -n |cut -d' ' -f2-
); do
  [ "${FILENAME#$key}" != "${FILENAME}" ] && \
  IFS=';' read -ra INITIATIVE_ALLOWED_CHARS <<< "${CARD_INITIATIVE_ALLOWED_CHARS[$key]}"
done

for key in $(printf "%s\n" "${!CARD_NUMBER_POS[@]}" |awk '{print length($0) " " $0}' |sort -n |cut -d' ' -f2-); do
  [ "${FILENAME#$key}" != "${FILENAME}" ] && NUMBER_POS=${CARD_NUMBER_POS[$key]}
done

output=$(jq --null-input --compact-output --arg image "${FILENAME#images/}" '.image=$image')

if [ "${SKIP_LEVEL}" -ne 1 ]; then
  log debug "$0: Parsing level from ${FILENAME} position ${LEVEL_POS}"
  # JOTL-hack to get the level from A/B card filename without OCR
  if [[ "${FILENAME}" =~ /.*\/jl-([ab]{1})-.* ]]; then
    level=$(tr '[:lower:]' '[:upper:]' <<< "${BASH_REMATCH[1]}")
  else
    level=$(
      try_get_text \
        "${FILENAME}" \
        "${LEVEL_POS}" \
        "${LEVEL_ALLOWED_CHARS}" \
        "${CARD_LEVEL_LENGTH}" \
        "${LEVEL_FGCOLOR}"
    )
  fi

  output=$(jq --compact-output --arg level "${level}" '.level=$level' <<< "${output}")
fi

if [ "${SKIP_INITIATIVE}" -ne 1 ]; then
  log debug "$0: Parsing initiative from ${FILENAME} position ${INITIATIVE_POS}"
  # Note: Input in array due to frosthaven/BB
  initiative=()
  for pos in "${INITIATIVE_POS[@]}"; do
    initiative+=($(
      try_get_text \
        "${FILENAME}" \
        "${pos}" \
        "${INITIATIVE_ALLOWED_CHARS}" \
        "${CARD_INITIATIVE_LENGTH}" \
        "white"
    ))
  done
  initiative=$(join_by ';' "${initiative[@]}")
  output=$(jq --compact-output --arg initiative "${initiative}" '.initiative=$initiative' <<< "${output}")
fi

if [ "${SKIP_CARDNO}" -ne 1 ]; then
  log debug "$0: Parsing cardno from ${FILENAME} position ${NUMBER_POS}"
  cardno=$(
    try_get_text \
      "${FILENAME}" \
      "${NUMBER_POS}" \
      "${CARD_NUMBER_ALLOWED_CHARS}" \
      "${CARD_NUMBER_LENGTH}" \
      "white"
  )
  output=$(jq --compact-output --arg cardno "${cardno}" '.cardno=$cardno' <<< "${output}")
fi

log debug "Output for ${FILENAME}: level=$level, initiative=$initiative, cardno=$cardno"
jq --compact-output <<< "${output}"
