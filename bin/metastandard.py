#!/usr/bin/env python3

"""
MetaStandard - Taxonomic Profile Unifier
=========================================
Merges and standardises taxonomic abundance profiles from metagenomic profiling
tools (currently mOTUs, MetaPhlAn 4 and Kraken2/Bracken) into a single, unified
TSV table.

WHAT IT DOES
------------
1. Auto-detects the profiling tool used based on input filenames.
2. Parses each sample's profile, filtering to the requested taxonomic level.
3. Normalises abundances to relative abundances (0-1 scale).
4. Standardises taxonomy strings (kingdom prefix, unclassified labels).
5. Merges all samples into one wide-format table (taxa x samples).
6. Writes the result to a TSV file.

INPUTS
------
--input   One or more taxonomic profile files (TSV/tabular format).
          Tool is auto-detected from the filename (checked in this order):
            - Files containing "motus"      -> parsed as mOTUs output
            - Files containing "metaphlan4" -> parsed as MetaPhlAn 4 output
            - Files containing "bracken"    -> parsed as Bracken output
          Sample names are derived from the filename:
            - mOTUs / MetaPhlAn 4: prefix before the first "_"
                e.g. "ERR001_motus_profile.tsv"        -> "ERR001"
            - Bracken: everything before ".bracken"
                e.g. "ERR001.bracken"                  -> "ERR001"
                     "ERR001_S1.bracken"               -> "ERR001_S1"
          For Bracken, pass both file types for each sample:
            - <sample>.bracken          (abundance table)
            - <sample>.bracken.mpa.txt  (lineage, from KrakenTools kreport2mpa.py
                                         run on Bracken's --out-report)

--level   Taxonomic level to extract.
            - mOTUs / MetaPhlAn 4: only "species" is supported.
            - Bracken: species, genus, family, order, class, phylum, kingdom
              (mapped to Bracken's S, G, F, O, C, P, K codes). Bracken output
              only contains the level it was run with (-l), so this must match.
          Default: species

--run_id  A label appended to the output filename to track run parameters.
          Default: run01

TOOL-SPECIFIC NOTES
-------------------
MetaPhlAn 4
  - Uses the relative abundance column (3rd column) of species rows (s__),
    excluding strain/SGB rows (t__).
  - The UNCLASSIFIED row is kept as the standardised unclassified entry.
  - Full lineage is kept; "|" separators are converted to ";".

mOTUs
  - Uses the abundance column (3rd column) and the Taxonomy column.
  - "unassigned" mOTUs and "s__Unknown..." species are relabelled as
    unclassified.
  - "d__" (domain) prefix is converted to "k__" (kingdom).

Bracken
  - Uses the "fraction_total_reads" column, which Bracken already reports
    on a 0-1 scale.
  - Full lineage is taken from the matching <sample>.bracken.mpa.txt file,
    matched on the taxon name. The NCBI kingdom rank (e.g. k__Pseudomonadati)
    is dropped and the domain d__ is renamed to k__, to match mOTUs and
    MetaPhlAn 4.
  - If the lineage file is missing or a name has no match, the TaxID falls
    back to the single rank, e.g. "s__Agathobacter_rectalis", with a warning.
  - If fractions sum to < 1, the remainder is added as the unclassified
    entry. Bracken fractions are computed over reads assigned at the chosen
    level, so this remainder is usually ~0; Kraken2-unclassified reads are
    NOT included.

OUTPUT
------
A tab-separated file named:  <tool>_<run_id>_<level>.tsv
Written to the current working directory.

Columns:
  TaxID    - Taxonomy string in semicolon-separated format
             mOTUs / MetaPhlAn 4 (full lineage):
               k__Bacteria;p__Firmicutes;...;s__Lactobacillus_acidophilus
             Bracken (full lineage from *.bracken.mpa.txt):
               k__Bacteria;p__Bacillota;...;s__Lactobacillus_acidophilus
  <sample> - Relative abundance (0-1) for each input sample

Unclassified and unassigned reads are aggregated under a standardised
"k__Unclassified;p__Unclassified;c__Unclassified;o__Unclassified;
f__Unclassified;g__Unclassified;s__Unclassified" taxonomy entry.

USAGE EXAMPLES
--------------
# Merge two MetaPhlAn 4 profiles at species level:
python metastandard.py \\
    --input sample1_metaphlan4.tsv sample2_metaphlan4.tsv \\
    --level species \\
    --run_id run01

# Merge mOTUs profiles with a custom run ID:
python metastandard.py \\
    --input sample1_motus.tsv sample2_motus.tsv \\
    --run_id experiment_A

# Merge Bracken species-level profiles (tables + lineage files):
python metastandard.py \\
    --input sample1.bracken sample1.bracken.mpa.txt \\
            sample2.bracken sample2.bracken.mpa.txt \\
    --level species \\
    --run_id run01

DEPENDENCIES
------------
  pandas

LIMITATIONS
-----------
- mOTUs and MetaPhlAn 4: only species-level output is implemented; other
  levels raise an error.
- Files from different tools cannot be mixed in a single run.
- Sample names are parsed from filenames; ensure consistent naming.
- NCBI lineages can skip ranks (e.g. no class), so Bracken TaxIDs may have
  fewer than 7 levels. Matching across tools on the s__ part is more robust.
- Taxonomy names depend on each tool's database (NCBI vs GTDB, and GTDB
  release), so the same organism may have different names across tools.
"""

import argparse
import pandas as pd
import os
import sys
import math

def parse_args():
    parser = argparse.ArgumentParser(description="MetaStandard: unify taxonomic profiles")

    parser.add_argument(
        "--input",
        nargs="+",
        required=True,
        help="Input taxonomic profiles"
    )

    parser.add_argument(
        "--level",
        default="species",
        help="Taxonomic level (species, genus, family...)"
    )
    
    parser.add_argument(
        "--run_id",
        default="run01",
        help="ID of the run in order to recognize the parameters used"
    )



    return parser.parse_args()


# -----------------------------

def detect_tool(files):
 
    if any("motus" in f.lower() for f in files):
        return "motus"
 
    if any("metaphlan4" in f.lower() for f in files):
        return "metaphlan4"
 
    if any("bracken" in f.lower() for f in files):
        return "bracken"
 
    return "unknown"


# -----------------------------

def read_profile(file, tool):
 
    if tool == "metaphlan4":
        header = None
    elif tool == "motus":
        header = 0
    elif tool == "bracken":
        header = 0
    df = pd.read_csv(file, sep="\t", comment="#", header=header)
 
    return df


# -----------------------------
def load_bracken_lineage(path, bracken_level):
    """
    Build a {name: lineage} map from a KrakenTools kreport2mpa.py file.

    Input lines look like:
        d__Bacteria|k__Pseudomonadati|p__Bacteroidota|...|s__Phocaeicola_vulgatus   68937

    Returns e.g.:
        {"Phocaeicola_vulgatus":
         "k__Bacteria;p__Bacteroidota;...;s__Phocaeicola_vulgatus"}

    Lineage is standardised to match mOTUs / MetaPhlAn 4:
        - NCBI kingdom rank (e.g. k__Pseudomonadati) is dropped
        - domain d__ -> k__
        - "|" -> ";"
    """
    if path is None:
        return {}

    prefix = "d__" if bracken_level == "K" else bracken_level.lower() + "__"

    mpa = pd.read_csv(path, sep="\t", header=None, comment="#",
                      names=["lineage", "reads"])

    last_rank = mpa["lineage"].str.split("|").str[-1]
    mpa = mpa[last_rank.str.startswith(prefix)].copy()
    mpa["key"] = mpa["lineage"].str.split("|").str[-1].str[len(prefix):]

    mpa["TaxID"] = (mpa["lineage"]
                    .str.replace(r"\|k__[^|]*", "", regex=True)
                    .str.replace("d__", "k__", regex=False)
                    .str.replace("|", ";", regex=False))

    mpa = mpa.drop_duplicates("key")
    return dict(zip(mpa["key"], mpa["TaxID"]))


# -----------------------------
def parse_bracken(files, level):
    """
    Parse Bracken output files and merge into a unified abundance table.
 
    Bracken output columns:
        name                    - Species name (e.g. "Agathobacter rectalis")
        taxonomy_id             - NCBI taxonomy ID
        taxonomy_lvl            - Taxonomic level (S, G, F, ...)
        kraken_assigned_reads   - Reads directly assigned by Kraken2
        added_reads             - Reads re-estimated by Bracken
        new_est_reads           - Total estimated reads (used for abundance)
        fraction_total_reads    - Fraction of total reads (0-1)
 
    Strategy:
        - Filter to the requested taxonomic level (e.g. "S" for species).
        - Look up the full lineage for each taxon in the matching
          <sample>.bracken.mpa.txt file (KrakenTools kreport2mpa.py output),
          matching on the name ("Phocaeicola vulgatus" <-> s__Phocaeicola_vulgatus).
        - If no lineage file or no match is found, fall back to the single-rank
          TaxID "s__<name with spaces replaced by _>" and print a warning.
        - Use fraction_total_reads as the abundance measure (already normalised 0-1).
        - Unclassified reads (not present in Bracken output) are not explicitly
          reported; if needed they can be inferred as 1 - sum(fraction_total_reads).
    """
    merged = []

    # Split inputs: Bracken tables (*.bracken) and lineage files (*.bracken.mpa.txt)
    profile_files = [f for f in files if f.endswith(".bracken")]
    lineage_files = {
        os.path.basename(f).split(".bracken")[0]: f
        for f in files if f.endswith(".mpa.txt")
    }
    if not profile_files:
        raise ValueError("No *.bracken files found in --input.")
 
    # Map requested level to Bracken's taxonomy_lvl codes
    level_map = {
        "species": "S",
        "genus":   "G",
        "family":  "F",
        "order":   "O",
        "class":   "C",
        "phylum":  "P",
        "kingdom": "K",
    }
 
    if level not in level_map:
        raise ValueError(f"Level '{level}' is not supported for Bracken parsing. "
                         f"Choose from: {list(level_map.keys())}")
 
    bracken_level = level_map[level]
 
    for f in profile_files:
        # Derive sample name from filename: everything before ".bracken"
        sample = os.path.basename(f).split(".bracken")[0]
 
        df = read_profile(f, tool="bracken")
 
        # Validate expected columns are present
        required_cols = {"name", "taxonomy_lvl", "fraction_total_reads"}
        if not required_cols.issubset(df.columns):
            raise ValueError(
                f"File {f} is missing required Bracken columns. "
                f"Expected at least: {required_cols}. Found: {set(df.columns)}"
            )
 
        # Filter to the requested taxonomic level
        df_sub = df[df["taxonomy_lvl"] == bracken_level].copy()
        df_sub = df_sub.reset_index(drop=True)
 
        # Map names to full lineage from the matching *.bracken.mpa.txt file
        lineage_path = lineage_files.get(sample)
        if lineage_path is None:
            print(f"WARNING: no lineage file (*.bracken.mpa.txt) for sample '{sample}'; "
                  f"using single-rank TaxIDs.", file=sys.stderr)
        lineage_map = load_bracken_lineage(lineage_path, bracken_level)

        key = df_sub["name"].str.replace(" ", "_", regex=False)
        df_sub["TaxID"] = key.map(lineage_map)

        # Fallback for names without a lineage match: "s__Species_name"
        out_prefix = "k__" if bracken_level == "K" else bracken_level.lower() + "__"
        missing = df_sub["TaxID"].isna()
        if missing.any() and lineage_path is not None:
            print(f"WARNING: {missing.sum()} taxa in '{sample}' had no lineage match; "
                  f"using single-rank TaxIDs for them.", file=sys.stderr)
        df_sub.loc[missing, "TaxID"] = out_prefix + key[missing]
 
        # Keep only TaxID and abundance
        df_sub = df_sub[["TaxID", "fraction_total_reads"]].copy()
        df_sub.columns = ["TaxID", sample]
 
        # Add unclassified remainder so all samples sum to 1
        classified_sum = df_sub[sample].sum()
        unclassified_fraction = 1.0 - classified_sum
        if unclassified_fraction > 1e-6:
            unclassified_taxid = (
                "k__Unclassified;p__Unclassified;c__Unclassified;"
                "o__Unclassified;f__Unclassified;g__Unclassified;s__Unclassified"
            )
            new_row = {"TaxID": unclassified_taxid, sample: unclassified_fraction}
            df_sub = pd.concat([df_sub, pd.DataFrame([new_row])], ignore_index=True)
 
        merged.append(df_sub)
 
    # Merge all samples into a wide table
    result = merged[0]
    for df in merged[1:]:
        result = result.merge(df, on="TaxID", how="outer")
 
    result = result.fillna(0)
 
    return result

# -----------------------------
def parse_metaphlan4(files,level):
    merged = []
    
    for f in files:
        sample = os.path.basename(f).split("_")[0]
        df = read_profile(f,tool="metaphlan4")
        unclassified = int(df[df[0] == "UNCLASSIFIED"].iloc[0, 2])

        if level=="species":
            # Keep only rows where first column contains 's__'
            df_sub = df[df.iloc[:, 0].str.contains("s__|clade")]
            # Remove rows containing t__
            df_sub = df_sub[~df_sub.iloc[:, 0].str.contains("t__")]
            # Reset index
            df_sub = df_sub.reset_index(drop=True)
            # Kepp only first and third column
            df_sub = df_sub.iloc[:, [0, 2]]
            # Rename the columns
            df_sub.columns = ["TaxID", sample]
            df_sub['TaxID'] = df_sub['TaxID'].str.replace('|', ';', regex=False)
            
            # add unclassified
            if unclassified>0:
                new_row = {"TaxID": "k__Unclassified;p__Unclassified;c__Unclassified;o__Unclassified;f__Unclassified;g__Unclassified;s__Unclassified", 
                           sample: unclassified}
                df_sub = pd.concat([df_sub, pd.DataFrame([new_row])], ignore_index=True)

        else: 
            raise ValueError("The other level than species was not implemented yet")
            
        # normalize sample 0-1
        abundance_sum = df_sub.loc[:,sample].sum()
            
        df_sub[sample] = df_sub[sample] / abundance_sum

        # Add the cleaned subdf to the list
        merged.append(df_sub)

    # Merge all the samples
    result = merged[0]

    for df in merged[1:]:
        result = result.merge(df, on="TaxID", how="outer")

    result = result.fillna(0)
    
    return(result)

def parse_motus(files,level):
    merged = []
    
    for f in files:
        sample = os.path.basename(f).split("_")[0]
        df = read_profile(f,tool="motus")
        # Change the taxonomy for unassigned ones
        df.loc[df["mOTU"].str.contains("unassigned", case=False, na=False), "Taxonomy"] = "k__Unclassified;p__Unclassified;c__Unclassified;o__Unclassified;f__Unclassified;g__Unclassified;s__Unclassified"
        
        # Change the "Domain" to "kingdom"
        df['Taxonomy'] = df['Taxonomy'].str.replace('d__', 'k__', regex=False)
        
        # Extract only the necessary columns
        df = df.iloc[:, [1, 2]]
        df.columns = ["TaxID", sample]
        
        # lets merge to one level
        if level=="species":
            df_sub=df.copy()
            df_sub["TaxID"] = df_sub["TaxID"].str.replace(r"s__Unknown[^;]*","s__Unclassified",regex=True)
        
        else: 
            raise ValueError("The other level than species was not implemented yet")
            
        # Calculate relative abundance
        abundance_sum = df_sub.loc[:,sample].sum()
        df_sub[sample] = df_sub[sample] / abundance_sum

            
        # Add the cleaned subdf to the list
        merged.append(df_sub)
    
    # Merge all the samples
    result = merged[0]
    
    for df in merged[1:]:
        result = result.merge(df, on="TaxID", how="outer")

    result = result.fillna(0)
    
    return(result)
    

def main():

    # get arguments
    args = parse_args()
    # detect the type of the tool to parse
    tool = detect_tool(args.input)
    # Parse the outputs with approriate function
    if tool=="motus": 
        result_df = parse_motus(args.input,args.level)
    elif tool=="metaphlan4":
        result_df = parse_metaphlan4(args.input,args.level)
    elif tool == "bracken":
        result_df = parse_bracken(args.input, args.level)
    else:
        raise ValueError(
            "Could not detect tool from filenames. "
            "Filenames must contain 'motus', 'metaphlan4', or 'bracken'."
        )
        
    # saving the final merged table
    outfile = f"{tool}_{args.run_id}_{args.level}.tsv"
    result_df.to_csv(outfile, sep="\t", index=False)


if __name__ == "__main__":
    main()