# WMGS Benchmarking Framework Tutorial

**Authors:**  
Petra Polakovicova¹, Alise Ponsero²  
¹ Institute for Clinical and Experimental Medicine, Prague, Czech Republic  
² Core Bioinformatics, Quadram Institute of Biosciences, Norwich, UK

---

## Table of Contents
1. [Installing Nextflow & Singularity](#1-installing-nextflow--singularity)
2. [Setting up the Pipeline](#2-setting-up-the-pipeline)
3. [Editing your Params](#3-editing-your-params)
4. [Running the Pipeline with Test Data](#4-running-the-pipeline-with-test-data)
5. [Looking at Results](#5-looking-at-results)
6. [Validating the Results](#6-validating-the-results)
7. [Possible Problems](#7-possible-problems)

---

## 1. Installing Nextflow & Singularity

The easiest way to get Nextflow and Singularity is to set up a dedicated Conda environment:

```bash
conda create --prefix </path/to/your/new/nf-env/> bioconda::nextflow
conda activate </path/to/your/new/nf-env/>
conda install conda-forge::singularity
```

---

## 2. Setting up the Pipeline

Clone the pipeline repository from GitHub and run the provided setup script. The script will interactively ask for an installation directory, where it will create two subdirectories: `databases/` for reference databases and `singularity_cache/` for container images:

```bash
git clone https://github.com/aponsero/nf-Infogut-WGS.git
cd nf-Infogut-WGS
bash setup_pipeline.sh
```

You should then see a screen similar to this. Provide your custom installation path when prompted:

```
======================================================================
  METAGENOMIC PROFILING PIPELINE - SETUP
======================================================================

No installation directory provided.

Please enter the full path where you want to install pipeline resources:
(This will create subdirectories: databases/ and singularity_cache/)

Installation directory: </path/to/your/installation/directory/>
```

Press Enter. The installation will take a couple of minutes. At the end, you should see something like this:

```
======================================================================
  SETUP COMPLETE!
======================================================================

[SUCCESS] 2026-03-04 11:47:49 - All resources downloaded and installed successfully

Installation Summary:
  - Installation directory: </path/to/your/installation/directory/>
  - Total time: 46 minutes 1 seconds

Resource Locations:
  - mOTUs database:       </path/to/your/installation/directory/>/databases/motus/db_mOTU
  - MetaPhlAn4 database:  </path/to/your/installation/directory/>/databases/metaphlan4/metaphlan_db
  - Kraken2 database:     </path/to/your/installation/directory/>/databases/kraken_db
  - Containers:           </path/to/your/installation/directory/>/singularity_cache/
  - Configuration:        </path/to/your/installation/directory/>/pipeline_paths.config
  - Log file:             </path/to/your/installation/directory/>/logs/setup_20260304_110207.log
```

---

## 3. Editing your Params

If the installation was successful, open `nextflow.config` and update `</path/to/your/installation/directory/>` in the following parameters:

```bash
params {
    singularity_cache_dir = '</path/to/your/installation/directory/>singularity_cache'
    database_cache_dir    = '</path/to/your/installation/directory/>databases'
    metaphlan_db          = '</path/to/your/installation/directory/>databases/metaphlan4/metaphlan_db'
    motus_db_host         = '</path/to/your/installation/directory/>/databases/motus/db_mOTU'
    kraken2_db            = '</path/to/your/installation/directory/>/databases/kraken_db'

}
```

---

## 4. Running the Pipeline with Test Data

Now you are ready to run the pipeline on prepared testing data, pre-prepared in the `test/` directory. It consists of two subsampled samples designed to run quickly (~5–10 minutes).

If you followed the steps above and updated `nextflow.config`, run:

```bash
nextflow run main.nf \
        --input test/test_samplesheet.csv \
        --outdir results
```

If everything runs fine, your screen will show something like this:

```
N E X T F L O W   ~  version 25.10.4
===================================
METAGENOMIC PROFILING PIPELINE
===================================
Input samplesheet : test/test_samplesheet.csv
Output directory  : results
===================================
[7d/14dfbf] FIX_HEADERS (1)                  [100%] 2 of 2 ✔
[17/a22d79] FASTQC_RAW (SRR061436-test)      [100%] 2 of 2 ✔
[60/f043d6] FASTP (SRR061436-test)           [100%] 2 of 2 ✔
[22/3143b6] FASTQC_CLEAN (SRR061436-test)    [100%] 2 of 2 ✔
[4a/a7a883] METAPHLAN4 (SRR061436-test)      [100%] 2 of 2 ✔
[27/25bc5b] MOTUS (SRR061436-test)           [100%] 2 of 2 ✔
[a6/bd14cd] KRAKEN2 (2)                      [100%] 2 of 2 ✔
[e3/ec237b] BRACKEN_READLEN (SRR061436-test) [100%] 2 of 2 ✔
[31/79a64f] BRACKEN (SRR061436-test)         [100%] 2 of 2 ✔
[68/6af9e1] KRAKENTOOLS (2)                  [100%] 2 of 2 ✔
[91/518eac] METAPHLAN_METASTANDARD           [100%] 1 of 1 ✔
[28/32d9da] MOTUS_METASTANDARD               [100%] 1 of 1 ✔
[86/ac1493] BRACKEN_METASTANDARD             [100%] 1 of 1 ✔
[25/3724e0] MULTIQC                          [100%] 1 of 1 ✔
Pipeline completed at: 2026-03-06T10:23:05.213553083+01:00
Execution status: SUCCESS
Duration: 5m 55s
Output directory: results
```

---

## 5. Looking at Results

After a successful run, a `results/` directory will be created inside `nf-Infogut-WGS/`. The most important outputs are in the `07_metastandard/` folder, which contains standardized TSV files from mOTUs and MetaPhlAn collapsed to species level using a unified format.

```bash
cd results/07_metastandard
ls
```

You will see three files:

```
metaphlan4_run01_species.tsv
motus_run01_species.tsv
bracken_run01_species.tsv
```

---

## 6. Validating the Results

Once completed, you can validate your results against the ground truth to check pipeline reproducibility. Navigate back to the `test/` folder first:

```bash
cd ../../test
```

Then run the validation script:

```bash
bash validate_results.sh
```

A successful validation will show:

```
Comparing 3 tools by content (column-order independent)...
----------------------------------------
✅ MATCH:    metaphlan4_TestRun_species.tsv  <->  metaphlan4_run01_species.tsv
✅ MATCH:    motus_TestRun_species.tsv  <->  motus_run01_species.tsv
✅ MATCH:    bracken_TestRun_species.tsv  <->  bracken_run01_species.tsv
----------------------------------------
Results: 3 passed, 0 failed
```

---

## 7. Possible Problems

**No space left on device error:**  
If the pipeline fails with this error, set a custom temp directory before running:

```bash
export SINGULARITY_TMPDIR=</path/to/your/desired/tmp>
```

**Other issues:**  
If you encounter a problem not covered here, please contact us:  
- petra.polakovicova@ikem.cz  
- alise.ponsero@quadram.ac.uk
