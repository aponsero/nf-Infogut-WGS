process MOTUS_DB {
    tag "motus_database"
    storeDir "${params.database_cache_dir}/motus"  // Use centralized cache dir
    
    output:
    path "motus_db", emit: db
    
    when:
    params.motus_db == null
    
    script:
    """
    mkdir -p motus_db
    
    # Download mOTUs database
    motus downloadDB \\
        -t ${task.cpus} \\
        -db motus_db
    """
}