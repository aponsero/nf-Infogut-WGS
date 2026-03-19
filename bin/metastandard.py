#!/usr/bin/env python3

"""
MetaStandard - Taxonomic Profile Unifier
=========================================
Merges and standardises taxonomic abundance profiles from metagenomic profiling
tools (currently mOTUs and MetaPhlAn 4) into a single, unified TSV table.

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
          Tool is auto-detected from the filename:
            - Files containing "motus"      -> parsed as mOTUs output
            - Files containing "metaphlan4" -> parsed as MetaPhlAn 4 output
          Sample names are derived from the filename prefix before the first "_".
          Example: "ERR001_motus_profile.tsv" -> sample name "ERR001"

--level   Taxonomic level to extract. Currently only "species" is supported.
          Default: species

--run_id  A label appended to the output filename to track run parameters.
          Default: run01

OUTPUT
------
A tab-separated file named:  <tool>_<run_id>_<level>.tsv
Written to the current working directory.

Columns:
  TaxID    - Full taxonomy string in semicolon-separated format
             e.g. k__Bacteria;p__Firmicutes;...;s__Lactobacillus_acidophilus
  <sample> - Relative abundance (0-1) for each input sample

Unclassified and unassigned reads are aggregated under a standardised
"k__Unclassified;...;s__Unclassified" taxonomy entry.

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

DEPENDENCIES
------------
  pandas

LIMITATIONS
-----------
- Only species-level output is currently implemented; other levels raise an error.
- mOTUs and MetaPhlAn 4 input files cannot be mixed in a single run.
- Sample names are parsed from filename prefixes; ensure consistent naming.
"""

import argparse
import pandas as pd
import os
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

    return "unknown"


# -----------------------------

def read_profile(file,tool):

    if tool=="metaphlan4":
        header=None
    elif tool=="motus":
        header=0
    df = pd.read_csv(file, sep="\t", comment="#",header=header)

    return df


# -----------------------------


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
        
    # saving the final merged table
    outfile = f"{tool}_{args.run_id}_{args.level}.tsv"
    result_df.to_csv(outfile, sep="\t", index=False)


if __name__ == "__main__":
    main()