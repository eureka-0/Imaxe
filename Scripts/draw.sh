#!/bin/bash

set -o pipefail

OUTPUT_FILE="./Images/sample_updating.png"
WAITING_SECONDS=20

echo "==== Stage 1: Drawing Sine Function ===="
gnuplot <<EOF
set terminal pngcairo size 1600,1200 enhanced font "sans,14"
set output "${OUTPUT_FILE}"
set title "Function Example: sin(x)" font "Arial,20"
set xlabel "X" font "Arial,16"
set ylabel "Y" font "Arial,16"
set grid
plot sin(x) title "sin(x)" lw 2 lc rgb "blue"
EOF

echo "Success! The initial graph has been saved to ${OUTPUT_FILE}."

for i in $(seq $WAITING_SECONDS -1 1); do
  echo "Waiting for $i seconds..."
  sleep 1
done

echo "==== Stage 2: Drawing Cubic Function ===="
gnuplot <<EOF
set terminal pngcairo size 1600,1200 enhanced font "sans,14"
set output "${OUTPUT_FILE}"
set title "Function Example: x^3" font "Arial,20"
set xlabel "X" font "Arial,16"
set ylabel "Y" font "Arial,16"
set grid
plot x**3 title "x^3" lw 2 lc rgb "red"
EOF

echo "Success! The updated graph has been saved to ${OUTPUT_FILE}."
