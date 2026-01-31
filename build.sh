#!/bin/bash

echo "Building AMXX Stats Mod..."

mkdir -p compiled

echo "Compiling stats_mod.sma..."
amxxpc -iinclude src/stats_mod.sma -ocompiled/stats_mod.amxx

if [ $? -eq 0 ]; then
	echo ""
	echo "Build successful!"
	echo "Output: compiled/stats_mod.amxx"
else
	echo ""
	echo "Build failed! Check errors above."
	exit 1
fi

