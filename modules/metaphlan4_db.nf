process METAPHLAN4_DB {
    tag "metaphlan4_database"
    storeDir "${params.database_cache_dir}/metaphlan4"  // Use centralized cache dir
    
    output:
    path "metaphlan_db", emit: db
    
    when:
    params.metaphlan_db == null
    
    script:
    """
    mkdir -p metaphlan_db
    
    metaphlan \\
        --install \\
        --index ${params.metaphlan_index} \\
        --bowtie2db metaphlan_db \\
        --nproc ${task.cpus}
    """
}