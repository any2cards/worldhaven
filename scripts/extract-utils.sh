#!/bin/bash

TESSERACT_POSTPROCESS='s/[)]/0/g; s/[][]/1/g; s/[\?Z]/2/g; s/[B]/6/g; s/[H]/8/g; s/[(]//g; s/\s//g'

# Create tempfile and delete it before script exits
export TMPDIR="$(mktemp --directory)"
function cleanup() {
  rm -rf "${TMPDIR}"
}
trap cleanup EXIT

log() {
  [ "${DEBUG}" -ne 1 ] && [ "${1^^}" = "DEBUG" ] && return
  >&2 echo -n "$(date -Is) [${1^^}] "
  shift
  >&2 echo "${@}"
}

# https://stackoverflow.com/a/17841619
function join_by {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}

# Extract and clean part of image for tesseract
extract_image_text() {
  position="${1}"
  fuzz="${2}"
  resize="${3:-100%}"
  fgcolor="${4:-white}"
  tmpfile=$(mktemp)

  if [ "${fgcolor}" = "white" ]; then
    convert \
      -extract "${position}" \
      -filter triangle \
      -resize "${resize}"% \
      -fill black \
      -fuzz "${fuzz}%" \
      +opaque "#FFFFFF" \
      -colorspace HSI \
      -channel B \
      -level 100%,0% \
      +channel \
      -colorspace sRGB \
      "${FILENAME}" "${tmpfile}"
  elif [ "${fgcolor}" = "black" ]; then
    convert \
      -extract "${position}" \
      -filter triangle \
      -resize "${resize}"% \
      -fuzz "${fuzz}%" \
      +opaque black \
      "${FILENAME}" "${tmpfile}"
  fi
  echo "${tmpfile}"
}

tesseract_process() {
  filename="${1}"

  tesseract "${filename}" stdout \
    --psm 7 \
    --tessdata-dir "$(realpath $(dirname $0))/tesseract" \
    -l glo 2>/dev/null
}

try_get_text() {
  filename="${1}"
  position="${2}"
  allowed_chars="${3}"
  expected_length="${4}"
  fgcolor="${5}"

  if [ -z "${fgcolor}" ]; then
    fgcolor=(white black)
  else
    fgcolor=("${fgcolor}")
  fi

  outputs=()
  for color in "${fgcolor[@]}"; do
    for fuzz in 50 40 30 20 10; do
      # Extract and clean the text part of the image
      tmpfile=$(extract_image_text "${position}" "${fuzz}" 200% "${color}")

      # OCR Process the image
      output=$(tesseract_process "${tmpfile}")
      output_processed=$(
        echo "${output}" \
          |tr '[:lower:]' '[:upper:]' \
          |sed -E "${TESSERACT_POSTPROCESS}" \
          |xargs -0
      )

      [ "${DEBUG}" -eq 1 ] && log debug "${FUNCNAME[0]}: Tesseract output processed=${output_processed}, raw=${output}"
      [ "${VISUALDEBUG}" -eq 1 ] && feh "${tmpfile}"

      # Verify that the output looks correct
      trimoutput=$(echo "${output_processed}" |tr -d -c "${allowed_chars}" |head -c ${expected_length})
      [ "${output_processed}" = "${trimoutput}" ] && outputs+=($output_processed)
    done
  done

  # The most common value
  output=$(printf '%s\n' "${outputs[@]}" |sort |uniq -c |sort -rn |head -1 |awk '{print $2}')
  [ "${DEBUG}" -eq 1 ] && log debug "${FUNCNAME[0]}: Tesseract outcome \"${output}\""
  echo "${output}"
}
