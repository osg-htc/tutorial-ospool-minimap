#!/bin/bash
# Use minimap2 to map the basecalled reads to the reference genome
minimap2 -ax map-ont Celegans_ref.mmi "$1" > "mapped_${1}_reads_to_genome.sam"