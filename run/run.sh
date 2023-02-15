#!/bin/bash

# ==============================================================================
#                           SETTINGS AND VARIABLES
# ==============================================================================

# Input files and settings
genome=data/genome/Colfi1_scaffolds.fasta
genome_id=Colfi1
species=colletotrichum_fioniriae
eggnog_db_dir=/fs/scratch/PAS0471/jelmer/refdata/eggnog

# Output files
genome_masked=results/repeatmasker/Colfi1_masked.fasta
orthodb_prots=data/ref_proteins/orthodb/orthodb_fungi_proteins.faa
colleto_prots=data/ref_proteins/colletotrichum/colletotrichum_all.faa
colleto_prots_zip=data/ref_proteins/colletotrichum/ncbi_dataset.zip
all_prots=data/ref_proteins/combined.faa


# ==============================================================================
# Take a look at the genome
micromamba activate /fs/ess/PAS0471/jelmer/conda/bbmap-38.96
stats.sh "$genome"
#> Main genome scaffold/contig total:     224/257
#> Main genome scaffold sequence total:   49.706 MB
#> scaffold/contig N50:                   1.789 MB/1.208 MB


# ==============================================================================
#                           STRUCTURAL ANNOTATION
# ==============================================================================
# Identify repeats
sbatch mcic-scripts/annot/repeatmodeler.sh -i "$genome" -o results/repeatmodeler
sbatch mcic-scripts/annot/repeatmasker.sh -i "$genome" -o "$genome_masked" \
    --genome_lib results/repeatmodeler/Colfi1_scaffolds-families.fa

# Download reference proteins for Braker -- Part I - OrthoDB
wget -P data/ref_proteins https://v100.orthodb.org/download/odb10_fungi_fasta.tar.gz
tar -xzvf data/ref_proteins/odb10_fungi_fasta.tar.gz -C data/ref_proteins/orthodb/fungi
cat data/ref_proteins/orthodb/fungi/Rawdata/*fs > "$orthodb_prots"

# Download reference proteins for Braker -- Part II - Colletotrichum
micromamba activate /fs/ess/PAS0471/jelmer/conda/ncbi-datasets
datasets download genome taxon "colletotrichum" --include protein --filename "$colleto_prots_zip"
unzip "$colleto_prots_zip" -d data/ref_proteins/colletotrichum
find data/ref_proteins/colletotrichum -name "protein.faa" -exec cat {} > "$colleto_prots" \;

# Combine protein datasets
cat "$orthodb_prots" "$colleto_prots" > "$all_prots"

# Run Braker 
outdir=results/braker && mkdir -p "$outdir" && rm -r "$outdir" # Braker complains if dir exists
sbatch mcic-scripts/annot/braker2.sh -i "$genome_masked" -o $outdir \
    --ref_prot "$all_prots" --species "$species" --more_args "--fungus"

#TODO - Consider using OrthoFiller
#https://gitlab.com/xonq/tutorials/-/blob/master/orthofiller.md


# ==============================================================================
#                           FUNCTIONAL ANNOTATION
# ==============================================================================
proteome=results/braker/braker/augustus.hints.aa  # 'augustus.hints.aa' output from Braker

# Run EggnogMapper
#sbatch mcic-scripts/annot/eggnogmap_dl.sh -o "$eggnog_db_dir" # => Not needed, already downloaded
sbatch mcic-scripts/annot/eggnogmap.sh -i "$proteome" -o results/eggnogmapper \
    --db_dir "$eggnog_db_dir" --out_prefix "$genome_id"

# Run DeepLoc
sbatch mcic-scripts/annot/deeploc.sh -i "$proteome" -o results/deeploc

# Run EffectorP
sbatch mcic-scripts/annot/effectorp.sh -i "$proteome" -o results/effectorp

# Run SignalP
sbatch mcic-scripts/annot/signalp.sh -i "$proteome" -o results/signalp

# Run DeepTMHMM2 using the webserver: https://dtu.biolib.com/DeepTMHMM
