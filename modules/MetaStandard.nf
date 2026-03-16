process METASTANDARD {
    publishDir "${params.outdir}/06_metastandard", mode: 'copy'

    input:
    path profile_files

    output:
    path "*.tsv"

    script:
    
    """
    python3 ${projectDir}/bin/metastandard.py \
        --input ${profile_files} \
        --level ${params.tax_level} \
        --run_id ${params.run_id}
    """
}

