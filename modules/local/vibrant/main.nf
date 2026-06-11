process VIBRANT {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/vibrant:1.2.1--hdfd78af_4':
        'quay.io/biocontainers/vibrant:1.2.1--hdfd78af_4' }"

    input:
    tuple val(meta), path(fasta)
    path db

    output:
    tuple val(meta), path("VIBRANT_${prefix}/**")                                                    , emit: results
    tuple val(meta), path("VIBRANT_${prefix}/VIBRANT_results_*/VIBRANT_genome_quality_*.tsv")        , emit: quality, optional: true
    tuple val(meta), path("VIBRANT_${prefix}/VIBRANT_phages_*/*.phages_combined.fna")                , emit: phages , optional: true
    // VIBRANT has no reliable CLI version flag → pin to the container tag (mirrors bacphlip's approach).
    tuple val("${task.process}"), val('vibrant'), val('1.2.1'), topic: versions, emit: versions_vibrant

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    prefix = task.ext.prefix ?: "${meta.id}"
    // VIBRANT needs an uncompressed nucleotide FASTA; -d points at the downloaded DB dir (databases/).
    def decompress = fasta.name.endsWith('.gz') ? "gunzip -c ${fasta} > ${prefix}.fna" : "cp ${fasta} ${prefix}.fna"
    def db_arg = db ? "-d ${db}" : ''
    """
    ${decompress}

    VIBRANT_run.py \\
        -i ${prefix}.fna \\
        -t ${task.cpus} \\
        ${db_arg} \\
        -folder . \\
        $args
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p VIBRANT_${prefix}/VIBRANT_results_${prefix}
    touch VIBRANT_${prefix}/VIBRANT_results_${prefix}/VIBRANT_genome_quality_${prefix}.tsv
    """
}
