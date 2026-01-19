process MOTUS {
    tag "$sample_id"
    publishDir "${params.outdir}/05_motus", mode: 'copy'
    
    input:
    tuple val(sample_id), path(read1), path(read2)
    
    output:
    path "${sample_id}_motus_profile.txt", emit: profile
    path "${sample_id}_motus.log", emit: log
    
    script:
    """
    motus profile \\
        -f ${read1} \\
        -r ${read2} \\
        -n ${sample_id} \\
        -t ${task.cpus} \\
        -g ${params.motus_marker_gene_cutoff} \\
        -l ${params.motus_min_length} \\
        -y ${params.motus_counting_mode} \\
        ${params.motus_extra_args} \\
        -o ${sample_id}_motus_profile.txt \\
        2> ${sample_id}_motus.log
    """
}