process FASTP {
    tag "$sample_id"
    publishDir "${params.outdir}/02_fastp", mode: 'copy'
    
    input:
    tuple val(sample_id), path(read1), path(read2)
    
    output:
    tuple val(sample_id), path("${sample_id}_R1.trimmed.fastq.gz"), path("${sample_id}_R2.trimmed.fastq.gz"), emit: reads
    path "${sample_id}.fastp.json", emit: json
    path "${sample_id}.fastp.html", emit: html
    
    script:
    // Adapter detection
    def adapter_detection = params.fastp_detect_adapter_for_pe ? "--detect_adapter_for_pe" : ""
    def adapter_seq = params.fastp_adapter_sequence ? "--adapter_sequence ${params.fastp_adapter_sequence}" : ""
    def adapter_seq_r2 = params.fastp_adapter_sequence_r2 ? "--adapter_sequence_r2 ${params.fastp_adapter_sequence_r2}" : ""
    
    // PolyG/PolyX trimming
    def trim_poly_g = params.fastp_trim_poly_g ? "--trim_poly_g" : ""
    def disable_trim_poly_g = params.fastp_disable_trim_poly_g ? "--disable_trim_poly_g" : ""
    def trim_poly_x = params.fastp_trim_poly_x ? "--trim_poly_x" : ""
    
    // Sliding window quality trimming
    def cut_front = params.fastp_cut_front ? "--cut_front" : ""
    def cut_tail = params.fastp_cut_tail ? "--cut_tail" : ""
    def cut_right = params.fastp_cut_right ? "--cut_right" : ""
    
    // Deduplication
    def dedup = params.fastp_dedup ? "--dedup" : ""
    
    // Complexity filter
    def complexity_filter = params.fastp_low_complexity_filter ? "--low_complexity_filter" : ""
    
    // Base correction
    def correction = params.fastp_correction ? "--correction" : ""
    
    """
    fastp \\
        -i ${read1} \\
        -I ${read2} \\
        -o ${sample_id}_R1.trimmed.fastq.gz \\
        -O ${sample_id}_R2.trimmed.fastq.gz \\
        --thread ${task.cpus} \\
        --qualified_quality_phred ${params.fastp_qualified_quality_phred} \\
        --unqualified_percent_limit ${params.fastp_unqualified_percent_limit} \\
        --length_required ${params.fastp_length_required} \\
        --length_limit ${params.fastp_length_limit} \\
        ${adapter_detection} \\
        ${adapter_seq} \\
        ${adapter_seq_r2} \\
        --trim_front1 ${params.fastp_trim_front1} \\
        --trim_tail1 ${params.fastp_trim_tail1} \\
        --trim_front2 ${params.fastp_trim_front2} \\
        --trim_tail2 ${params.fastp_trim_tail2} \\
        ${cut_front} \\
        ${cut_tail} \\
        ${cut_right} \\
        --cut_window_size ${params.fastp_cut_window_size} \\
        --cut_mean_quality ${params.fastp_cut_mean_quality} \\
        ${trim_poly_g} \\
        ${disable_trim_poly_g} \\
        ${trim_poly_x} \\
        ${dedup} \\
        ${complexity_filter} \\
        --complexity_threshold ${params.fastp_complexity_threshold} \\
        ${correction} \\
        --n_base_limit ${params.fastp_n_base_limit} \\
        --average_qual ${params.fastp_average_qual} \\
        --compression ${params.fastp_compression} \\
        --json ${sample_id}.fastp.json \\
        --html ${sample_id}.fastp.html \\
        ${params.fastp_extra_args}
    """
}