process MULTIQC {
    publishDir "${params.outdir}/06_multiqc", mode: 'copy'
    
    input:
    path('*')
    
    output:
    path "multiqc_report.html", emit: html
    path "multiqc_report_data", emit: data
    
    script:
    def config = params.multiqc_config ? "--config ${params.multiqc_config}" : ""
    
    """
    multiqc . \\
        --title "${params.multiqc_title}" \\
        --filename multiqc_report \\
        --force \\
        --interactive \\
        ${config} \\
        ${params.multiqc_extra_args}
    """
}