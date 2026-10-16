process KRAKEN2 {
    input:
    tuple val(sample_id), path(read1), path(read2)
    path db_files, stageAs: 'k2db/*'     // hash.k2d, opts.k2d, taxo.k2d

    output:
    tuple val(sample_id), path("${sample_id}.kreport"), emit: kraken_report

    script:
    
    def confidence    = params.kraken2_confidence          != null ? "--confidence ${params.kraken2_confidence}"                   : ""
    def min_base_qual = params.kraken2_min_base_quality    != null ? "--minimum-base-quality ${params.kraken2_min_base_quality}"   : ""
    def min_hit_grp   = params.kraken2_min_hit_groups      != null ? "--minimum-hit-groups ${params.kraken2_min_hit_groups}"       : ""
    def quick         = params.kraken2_quick                ? "--quick"                 : ""

    // Memory
    def mmap          = params.kraken2_memory_mapping       ? "--memory-mapping"        : ""

    // Report options
    def zero_counts   = params.kraken2_report_zero_counts   ? "--report-zero-counts"    : ""
    def minimizer     = params.kraken2_report_minimizer_data ? "--report-minimizer-data" : ""
    def use_names     = params.kraken2_use_names            ? "--use-names"             : ""

    // Optional read outputs ('#' is replaced by _1/_2 for paired data)
    def classified    = params.kraken2_save_classified      ? "--classified-out ${sample_id}_classified_#.fq"     : ""
    def unclassified  = params.kraken2_save_unclassified    ? "--unclassified-out ${sample_id}_unclassified_#.fq" : ""

    // Per-read output is very large; keep it only if asked
    def per_read_out  = params.kraken2_save_output ? "${sample_id}_kraken.txt" : "/dev/null"

    """
    k2 classify \\
        --db k2db \\
        --threads ${task.cpus} \\
        --paired \\
        ${confidence} \\
        ${min_base_qual} \\
        ${min_hit_grp} \\
        ${quick} \\
        ${mmap} \\
        ${use_names} \\
        ${zero_counts} \\
        ${minimizer} \\
        ${classified} \\
        ${unclassified} \\
        ${params.kraken2_extra_args} \\
        --report ${sample_id}.kreport \\
        --output ${per_read_out} \\
        ${read1} ${read2}

    """
}


process BRACKEN {
    tag "${sample_id}"
    publishDir "${params.outdir}/06_bracken", mode: 'copy'

    input:
    tuple val(sample_id), path(kraken_report)
    path db

    output:
    path "${sample_id}.bracken",                                 emit: bracken_profile
    tuple val(sample_id), path("${sample_id}.bracken.kreport"),  emit: bracken_kreport

    script:
    def level     = params.bracken_level
    def threshold = params.bracken_threshold

    """
    est_abundance.py \\
        -i ${kraken_report} \\
        -k ${db} \\
        -l ${level} \\
        -t ${threshold} \\
        -o ${sample_id}.bracken \\
        --out-report ${sample_id}.bracken.kreport
    """
}

process KRAKENTOOLS {
    publishDir "${params.outdir}/06_bracken", mode: 'copy'
    
    input:
    tuple(val(sample_id), path(bracken_kreport))

    output:
    path "${sample_id}.bracken.mpa.txt", emit: bracken_profile_mpa

    script:
    """
    kreport2mpa.py -r ${sample_id}.bracken.kreport -o ${sample_id}.bracken.mpa.txt
    """
}