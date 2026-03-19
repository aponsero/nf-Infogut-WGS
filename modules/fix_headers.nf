process FIX_HEADERS {
    input:
    tuple val(sample_id), path(read1), path(read2)
    
    output:
    tuple val(sample_id), path("${sample_id}-fixed_1.fastq.gz"), path("${sample_id}-fixed_2.fastq.gz"), emit: reads

    script:
    """
    rename.sh \\
        in=${read1} \\
        in2=${read2} \\
        out=${sample_id}-fixed_1.fastq.gz \\
        out2=${sample_id}-fixed_2.fastq.gz

    """
}
