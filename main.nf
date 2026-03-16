#!/usr/bin/env nextflow

nextflow.enable.dsl=2

/*
========================================================================================
    METAGENOMIC PROFILING PIPELINE
========================================================================================
    Fastp -> FastQC -> MetaPhlAn4 + mOTUs -> MultiQC
----------------------------------------------------------------------------------------
*/

// Print pipeline header
log.info """\
    ===================================
    METAGENOMIC PROFILING PIPELINE
    ===================================
    Input samplesheet : ${params.input}
    Output directory  : ${params.outdir}
    ===================================
    """
    .stripIndent()

/*
========================================================================================
    IMPORT MODULES
========================================================================================
*/

include { FASTQC as FASTQC_RAW }   from './modules/fastqc'
include { FASTP }                   from './modules/fastp'
include { FASTQC as FASTQC_CLEAN } from './modules/fastqc'
include { METAPHLAN4_DB }           from './modules/metaphlan4_db'
include { METAPHLAN4 }              from './modules/metaphlan4'
include { MOTUS }                   from './modules/motus'
include { MULTIQC }                 from './modules/multiqc'
include { METASTANDARD as METAPHLAN_METASTANDARD }        from './modules/MetaStandard'
include { METASTANDARD as MOTUS_METASTANDARD }       from './modules/MetaStandard'
/*
========================================================================================
    MAIN WORKFLOW
========================================================================================
*/

workflow {
    
    // Validate mOTUs database path
    if (!params.motus_db_host) {
        exit 1, "ERROR: --motus_db_host must be specified. Please provide the path to your mOTUs database."
    }
    if (!file(params.motus_db_host).exists()) {
        exit 1, "ERROR: mOTUs database not found at: ${params.motus_db_host}"
    }
    
    // Read and parse samplesheet
    Channel
        .fromPath(params.input)
        .splitCsv(header: true)
        .map { row -> 
            def sample_id = row.sample
            def read1 = file(row.read1)
            def read2 = file(row.read2)
            
            // Validate files exist
            if (!read1.exists()) exit 1, "ERROR: Read1 file does not exist: ${read1}"
            if (!read2.exists()) exit 1, "ERROR: Read2 file does not exist: ${read2}"
            
            return tuple(sample_id, read1, read2)
        }
        .set { ch_input_reads }
    
    // Setup MetaPhlAn4 database if not provided
    if (params.metaphlan_db == null) {
        METAPHLAN4_DB()
        ch_metaphlan_db = METAPHLAN4_DB.out.db
    } else {
        ch_metaphlan_db = Channel.value(file(params.metaphlan_db))
    }
    
    // FastQC on raw reads
    FASTQC_RAW(ch_input_reads, "raw")
    
    // Fastp trimming and filtering
    FASTP(ch_input_reads)
    
    // FastQC on cleaned reads
    FASTQC_CLEAN(FASTP.out.reads, "clean")
    
    // MetaPhlAn4 profiling (parallel)
    METAPHLAN4(FASTP.out.reads, ch_metaphlan_db)
    
    // mOTUs profiling (parallel) - database mounted via containerOptions
    MOTUS(FASTP.out.reads)
    
    // MetaStandard - format standardization
    motus_files = MOTUS.out.profile.collect()
    metaphlan_files = METAPHLAN4.out.profile.collect()

    METAPHLAN_METASTANDARD(metaphlan_files)
    MOTUS_METASTANDARD(motus_files)

    // Collect all QC files for MultiQC
    ch_multiqc_files = Channel.empty()
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC_RAW.out.zip.collect().ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(FASTP.out.json.collect().ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC_CLEAN.out.zip.collect().ifEmpty([]))
    
    // MultiQC aggregation
    MULTIQC(ch_multiqc_files.collect())
}

/*
========================================================================================
    WORKFLOW COMPLETION
========================================================================================
*/

workflow.onComplete {
    log.info """\
        Pipeline completed at: ${workflow.complete}
        Execution status: ${workflow.success ? 'SUCCESS' : 'FAILED'}
        Duration: ${workflow.duration}
        Output directory: ${params.outdir}
        """
        .stripIndent()
}