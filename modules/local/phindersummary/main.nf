process PHINDERSUMMARY {
    tag "phinder_summary"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/pandas:1.5.2':
        'quay.io/biocontainers/pandas:1.5.2' }"

    input:
    // Fan-in: all per-sample reports collected across the run. Each is a (possibly empty) list of files.
    path('checkv/*')
    path('quast/*')
    path('pharokka/*')
    path('bacphlip/*')
    path('vibrant/*')

    output:
    path("phinder_summary.tsv") , emit: tsv
    path("phinder_summary.html"), emit: html
    tuple val("${task.process}"), val('python'), eval("python --version | sed 's/Python //'"), topic: versions, emit: versions_python

    when:
    task.ext.when == null || task.ext.when

    script:
    // REVIEW: this is a scaffolded aggregator. Port the real integration logic from PHINDER's bin/ here
    //         (column selection, per-tool parsing, HTML layout). It currently concatenates whatever it finds.
    """
    summarize_phinder.py \\
        --checkv checkv \\
        --quast quast \\
        --pharokka pharokka \\
        --bacphlip bacphlip \\
        --vibrant vibrant \\
        --out-tsv phinder_summary.tsv \\
        --out-html phinder_summary.html
    """

    stub:
    """
    touch phinder_summary.tsv phinder_summary.html
    """
}
