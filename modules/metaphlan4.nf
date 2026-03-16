process METAPHLAN4 {
    tag "$sample_id"
    publishDir "${params.outdir}/04_metaphlan4", mode: 'copy'
    
    input:
    tuple val(sample_id), path(read1), path(read2)
    path(db)
    
    output:
    path "${sample_id}_metaphlan4_profile.txt", emit: profile
    path "${sample_id}.mapout.bz2", emit: mapout, optional: true
    
    script:
    // Database options
    def db_option = "--db_dir ${db}"
    
    // Taxonomic filtering
    def ignore_eukaryotes = params.metaphlan_ignore_eukaryotes ? "--ignore_eukaryotes" : ""
    def ignore_bacteria = params.metaphlan_ignore_bacteria ? "--ignore_bacteria" : ""
    def ignore_archaea = params.metaphlan_ignore_archaea ? "--ignore_archaea" : ""
    
    // Markers
    def ignore_markers = params.metaphlan_ignore_markers ? "--ignore_markers ${params.metaphlan_ignore_markers}" : ""
    
    // Min alignment length (only add if not null)
    def min_alignment_len = params.metaphlan_min_alignment_len ? "--min_alignment_len ${params.metaphlan_min_alignment_len}" : ""
    
    // Other options
    def offline = params.metaphlan_offline ? "--offline" : ""
    def verbose = params.metaphlan_verbose ? "--verbose" : ""
    
    """
    metaphlan \\
        ${read1},${read2} \\
        --input_type fastq \\
        --nproc ${task.cpus} \\
        ${db_option} \\
        --index ${params.metaphlan_index} \\
        --mapout ${sample_id}.mapout.bz2 \\
        --bt2_ps ${params.metaphlan_bt2_ps} \\
        --tax_lev ${params.metaphlan_tax_level} \\
        ${min_alignment_len} \\
        --stat_q ${params.metaphlan_stat_q} \\
        --perc_nonzero ${params.metaphlan_perc_nonzero} \\
        --stat ${params.metaphlan_stat} \\
        -t ${params.metaphlan_analysis_type} \\
        --read_min_len ${params.metaphlan_read_min_len} \\
        --min_mapq_val ${params.metaphlan_min_mapq_val} \\
        ${ignore_eukaryotes} \\
        ${ignore_bacteria} \\
        ${ignore_archaea} \\
        ${ignore_markers} \\
        ${offline} \\
        ${verbose} \\
        --sample_id ${sample_id} \\
        ${params.metaphlan_extra_args} \\
        -o ${sample_id}_metaphlan4_profile.txt 
    """
}