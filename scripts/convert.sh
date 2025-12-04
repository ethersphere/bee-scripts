#!/bin/bash

# This script converts between BZZ and PLUR units.
# PLUR is the smallest unit (like wei), and BZZ is the main unit.
# Conversion factor: 1 BZZ = 10^16 PLUR
# Requirements:
# - bc (for precision arithmetic)
# Usage: ./convert.sh [VALUE] [UNIT]
# Example: ./convert.sh 1 BZZ
# Example: ./convert.sh 100000 PLUR
# Example: ./convert.sh 1.5 bzz
# Example: ./convert.sh 117000000 plur

# Check if arguments are provided
if [ $# -lt 2 ]; then
  echo "Error: Please provide a value and unit (BZZ or PLUR)."
  echo "Usage: ./convert.sh [VALUE] [UNIT]"
  echo "Example: ./convert.sh 1 BZZ"
  echo "Example: ./convert.sh 100000 PLUR"
  exit 1
fi

VALUE=$1
UNIT=$(echo "$2" | tr '[:lower:]' '[:upper:]')

# Validate that VALUE is a number
if ! [[ "$VALUE" =~ ^[0-9]+\.?[0-9]*$ ]]; then
  echo "❌ Error: '$VALUE' is not a valid number."
  exit 1
fi

# Validate unit
if [ "$UNIT" != "BZZ" ] && [ "$UNIT" != "PLUR" ]; then
  echo "❌ Error: Unit must be 'BZZ' or 'PLUR' (case-insensitive)."
  echo "   Received: $2"
  exit 1
fi

# Conversion factor: 1 BZZ = 10^16 PLUR
CONVERSION_FACTOR=10000000000000000

echo "🔄 Converting $VALUE $UNIT..."
echo "---"

if [ "$UNIT" == "BZZ" ]; then
  # Convert BZZ to PLUR: multiply by 10^16
  PLUR_AMOUNT=$(bc -l <<EOF
    scale=0
    ${VALUE} * ${CONVERSION_FACTOR}
EOF
  )
  
  printf "📊 Result:\n"
  printf "   %s BZZ = %s PLUR\n" "$VALUE" "$PLUR_AMOUNT"
  printf "   (1 BZZ = %s PLUR)\n" "$CONVERSION_FACTOR"
  
elif [ "$UNIT" == "PLUR" ]; then
  # Convert PLUR to BZZ: divide by 10^16
  BZZ_AMOUNT=$(bc -l <<EOF
    scale=18
    ${VALUE} / ${CONVERSION_FACTOR}
EOF
  )
  
  printf "📊 Result:\n"
  printf "   %s PLUR = %s BZZ\n" "$VALUE" "$BZZ_AMOUNT"
  printf "   (1 PLUR = %s BZZ)\n" "0.0000000000000001"
fi
