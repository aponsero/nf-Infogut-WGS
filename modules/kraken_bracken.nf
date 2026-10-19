process KRAKEN2 {
    input:
    tuple val(sample_id), path(read1), path(read2)
    path db_files
    
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
        --db ${db_files} \\
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

process BRACKEN_READLEN {
    tag "${sample_id}"

    input:
    tuple val(sample_id), path(read1), path(read2)
    path kraken2_dbs

    output:
    tuple val(sample_id), env(READ_LEN),           emit: read_len

    script:
    def r1 = read1

    """
    # Median read length of the first 1000 reads (R1)
    case "${r1}" in
        *.gz) DECOMP="gzip -dc" ;;
        *)    DECOMP="cat" ;;
    esac

    # '|| true' absorbs the SIGPIPE when awk exits early
    { \$DECOMP ${r1} || true; } \\
        | awk -v max=1000 'NR % 4 == 2 { print length(\$0); n++ } n >= max { exit }' \\
        | sort -n > read_lengths.txt

    N=\$(wc -l < read_lengths.txt)
    if [ "\$N" -eq 0 ]; then
        echo "ERROR: no reads found in ${r1}" >&2
        exit 1
    fi

    MEDIAN=\$(awk -v n="\$N" '{ a[NR] = \$1 }
        END { if (n % 2) print a[(n + 1) / 2]; else print int((a[n / 2] + a[n / 2 + 1]) / 2) }' read_lengths.txt)

    # Pick the closest available kmer_distrib (ties -> shorter)
    READ_LEN=\$( { ls ${kraken2_dbs} 2>/dev/null || true; } \\
        | sed -E 's/.*database([0-9]+)mers\\.kmer_distrib/\\1/' \\
        | sort -n \\
        | awk -v m="\$MEDIAN" '{ d = (\$1 > m) ? \$1 - m : m - \$1
                                 if (bd == "" || d < bd) { bd = d; best = \$1 } }
                               END { print best }')

    if [ -z "\$READ_LEN" ]; then
        echo "ERROR: no database*mers.kmer_distrib files in ${kraken2_dbs}" >&2
        exit 1
    fi

    printf "sample\\tmedian_read_length\\tbracken_read_length\\n${sample_id}\\t%s\\t%s\\n" \\
        "\$MEDIAN" "\$READ_LEN" > ${sample_id}.read_length.tsv
    echo "[${sample_id}] median read length: \$MEDIAN -> using database\${READ_LEN}mers.kmer_distrib"
    """
}

process BRACKEN {
    tag "${sample_id}"
    publishDir "${params.outdir}/06_bracken", mode: 'copy'

    input:
    tuple val(sample_id), path(kraken_report), path(db)

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