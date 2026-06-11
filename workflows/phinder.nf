/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
// QC / read prep
include { FASTQC                    } from '../modules/nf-core/fastqc/main'
include { FASTP                     } from '../modules/nf-core/fastp/main'
include { NANOPLOT                  } from '../modules/nf-core/nanoplot/main'
include { PORECHOP_PORECHOP         } from '../modules/nf-core/porechop/porechop/main'
include { FILTLONG                  } from '../modules/nf-core/filtlong/main'
// Assembly
include { UNICYCLER                 } from '../modules/nf-core/unicycler/main'
include { FLYE                      } from '../modules/nf-core/flye/main'
include { MEDAKA                    } from '../modules/nf-core/medaka/main'
// Characterization
include { QUAST                     } from '../modules/nf-core/quast/main'
include { CHECKV_DOWNLOADDATABASE   } from '../modules/nf-core/checkv/downloaddatabase/main'
include { CHECKV_ENDTOEND           } from '../modules/nf-core/checkv/endtoend/main'
include { PHAROKKA_INSTALLDATABASES } from '../modules/nf-core/pharokka/installdatabases/main'
include { PHAROKKA_PHAROKKA         } from '../modules/nf-core/pharokka/pharokka/main'
include { VIBRANT                   } from '../modules/local/vibrant/main'
include { BACPHLIP                  } from '../modules/nf-core/bacphlip/main'
include { DIAMOND_MAKEDB            } from '../modules/nf-core/diamond/makedb/main'
include { DIAMOND_BLASTX            } from '../modules/nf-core/diamond/blastx/main'
// SRA input mode (input_mode == 'sra')  // TODO(sra): add an `sra_accession` column to schema_input.json and wire below.
include { SRATOOLS_PREFETCH         } from '../modules/nf-core/sratools/prefetch/main'
include { SRATOOLS_FASTERQDUMP      } from '../modules/nf-core/sratools/fasterqdump/main'
// Report
include { MULTIQC                   } from '../modules/nf-core/multiqc/main'
include { PHINDERSUMMARY            } from '../modules/local/phindersummary/main'

include { paramsSummaryMap          } from 'plugin/nf-schema'
include { paramsSummaryMultiqc      } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML    } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText    } from '../subworkflows/local/utils_nfcore_phinder_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow PHINDER {

    take:
    ch_samplesheet // channel: [ meta, shortreads(list), longreads(path|[]), fasta(path|[]) ]
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:

    def ch_versions       = channel.empty()
    def ch_multiqc_files   = channel.empty()
    // Per-tool report accumulators that feed the custom PHINDERSUMMARY fan-in.
    def ch_quast_rep       = channel.empty()
    def ch_checkv_rep      = channel.empty()
    def ch_pharokka_rep    = channel.empty()
    def ch_bacphlip_rep    = channel.empty()
    def ch_vibrant_rep     = channel.empty()

    //
    // REVIEW: split samples by input mode. 'assembly' rows skip QC+assembly and enter at QUAST.
    //
    def ch_branched = ch_samplesheet.branch { meta, _sr, _lr, _fa ->
        assembly: meta.mode == 'assembly'
        reads   : true
    }

    //
    // READ-TYPE TRACKS (a hybrid sample appears in BOTH the short and long tracks)
    //
    // REVIEW: empty list ([]) is falsy in Groovy, so these filters select on read presence.
    def ch_short_raw = ch_branched.reads
        .filter { _meta, sr, _lr, _fa -> sr }
        .map    { meta, sr, _lr, _fa -> [ meta, sr ] }
    def ch_long_raw = ch_branched.reads
        .filter { _meta, _sr, lr, _fa -> lr }
        .map    { meta, _sr, lr, _fa -> [ meta, lr ] }

    //
    // SHORT-READ QC + TRIM (short + hybrid)
    //
    FASTQC( ch_short_raw )
    ch_multiqc_files = ch_multiqc_files.mix( FASTQC.out.zip.map { _meta, f -> f } )

    // fastp input tuple is [meta, reads, adapter_fasta]; trailing 3 vals: discard_trimmed_pass, save_trimmed_fail, save_merged
    FASTP( ch_short_raw.map { meta, sr -> [ meta, sr, [] ] }, false, false, false )
    ch_multiqc_files = ch_multiqc_files.mix( FASTP.out.json.map { _meta, f -> f } )

    //
    // LONG-READ QC + FILTER (long + hybrid)
    //
    NANOPLOT( ch_long_raw )
    ch_multiqc_files = ch_multiqc_files.mix( NANOPLOT.out.txt.map { _meta, f -> f } )
    ch_versions      = ch_versions.mix( NANOPLOT.out.versions )

    PORECHOP_PORECHOP( ch_long_raw )
    ch_multiqc_files = ch_multiqc_files.mix( PORECHOP_PORECHOP.out.log.map { _meta, f -> f } )
    ch_versions      = ch_versions.mix( PORECHOP_PORECHOP.out.versions )

    // FILTLONG input is [meta, shortreads, longreads]; long-only filtering -> shortreads = []
    FILTLONG( PORECHOP_PORECHOP.out.reads.map { meta, r -> [ meta, [], r ] } )
    def ch_long_clean = FILTLONG.out.reads   // [meta, filtered_long]

    //
    // ASSEMBLY (branch by mode; all paths converge to ch_assembly = [meta, fasta])
    //
    // Unicycler handles short-only AND hybrid via [meta, shortreads, longreads].
    // REVIEW: join short(trimmed) with long(filtered) by meta.id; remainder keeps short-only rows (no long mate).
    def ch_unicycler_in = FASTP.out.reads
        .map { meta, sr -> [ meta.id, meta, sr ] }
        .join( ch_long_clean.map { meta, lr -> [ meta.id, lr ] }, remainder: true )
        .filter { _id, meta, _sr, _lr -> meta != null }   // drop long-only rows (no short mate)
        .map { _id, meta, sr, lr -> [ meta, sr, lr ?: [] ] }
    UNICYCLER( ch_unicycler_in )
    ch_versions = ch_versions.mix( UNICYCLER.out.versions )

    // Flye + Medaka for long-only samples (hybrid long reads went to Unicycler).
    def ch_flye_in = ch_long_clean.filter { meta, _lr -> meta.mode == 'long' }
    FLYE( ch_flye_in, params.flye_mode )

    // REVIEW: Medaka needs [meta, reads, assembly] — join filtered long reads with the Flye assembly by meta.id.
    def ch_medaka_in = ch_flye_in
        .map { meta, lr -> [ meta.id, meta, lr ] }
        .join( FLYE.out.fasta.map { meta, fa -> [ meta.id, fa ] } )
        .map { _id, meta, lr, fa -> [ meta, lr, fa ] }
    MEDAKA( ch_medaka_in )

    // Converge: Unicycler scaffolds + Medaka-polished long assemblies + pre-assembled FASTA (assembly mode).
    def ch_assembly = UNICYCLER.out.scaffolds
        .mix( MEDAKA.out.assembly )
        .mix( ch_branched.assembly.map { meta, _sr, _lr, fa -> [ meta, fa ] } )

    //
    // ASSEMBLY QC — QUAST (de novo: no reference fasta/gff -> empty placeholders)
    //
    QUAST( ch_assembly, [ [:], [] ], [ [:], [] ] )
    ch_quast_rep     = ch_quast_rep.mix( QUAST.out.results.map { _meta, d -> d } )
    ch_multiqc_files = ch_multiqc_files.mix( QUAST.out.results.map { _meta, d -> d } )

    //
    // COMPLETENESS — CheckV
    //
    if (!params.skip_checkv) {
        // REVIEW: value channel for the shared DB. Download dir contents if no path supplied.
        def ch_checkv_db = params.checkv_db
            ? channel.value( file(params.checkv_db) )
            : CHECKV_DOWNLOADDATABASE().checkv_db.collect()
        CHECKV_ENDTOEND( ch_assembly, ch_checkv_db )
        ch_checkv_rep = ch_checkv_rep.mix( CHECKV_ENDTOEND.out.quality_summary.map { _meta, f -> f } )
    }

    //
    // ANNOTATION — Pharokka (PHANOTATE gene-calling is internal)
    //
    // REVIEW: value channel for the shared Pharokka DB; download if no path supplied.
    def ch_pharokka_db = params.pharokka_db
        ? channel.value( file(params.pharokka_db) )
        : PHAROKKA_INSTALLDATABASES().pharokka_db.collect()
    PHAROKKA_PHAROKKA( ch_assembly, ch_pharokka_db )
    ch_versions     = ch_versions.mix( PHAROKKA_PHAROKKA.out.versions )
    ch_pharokka_rep = ch_pharokka_rep.mix( PHAROKKA_PHAROKKA.out.cds_functions.map { _meta, f -> f } )

    //
    // LIFESTYLE — VIBRANT (custom) + BACPHLIP
    //
    if (!params.skip_vibrant) {
        // REVIEW: vibrant_db is user-supplied (no download module); required when VIBRANT is enabled.
        def ch_vibrant_db = params.vibrant_db ? channel.value( file(params.vibrant_db) ) : channel.value( [] )
        VIBRANT( ch_assembly, ch_vibrant_db )
        ch_vibrant_rep = ch_vibrant_rep.mix( VIBRANT.out.quality.map { _meta, f -> f } )
    }
    if (!params.skip_bacphlip) {
        BACPHLIP( ch_assembly )
        ch_bacphlip_rep = ch_bacphlip_rep.mix( BACPHLIP.out.bacphlip_results.map { _meta, f -> f } )
    }

    //
    // PROPHAGE COMPARISON — DIAMOND (build DB once, then blastx per sample)
    //
    if (!params.skip_diamond) {
        // REVIEW: prophage_db is a reference FASTA; built once into a value channel shared across samples.
        def ch_prophage_fa = channel.value( [ [ id:'prophage_db' ], file(params.prophage_db) ] )
        DIAMOND_MAKEDB( ch_prophage_fa, [], [], [] )
        DIAMOND_BLASTX( ch_assembly, DIAMOND_MAKEDB.out.db.first(), 'txt', [] )
    }

    //
    // INTEGRATED REPORT — custom fan-in across all per-sample tool outputs
    //
    PHINDERSUMMARY(
        ch_checkv_rep.collect().ifEmpty( [] ),
        ch_quast_rep.collect().ifEmpty( [] ),
        ch_pharokka_rep.collect().ifEmpty( [] ),
        ch_bacphlip_rep.collect().ifEmpty( [] ),
        ch_vibrant_rep.collect().ifEmpty( [] )
    )

    // TODO(nf-multiqc): CheckV, Pharokka, VIBRANT, BACPHLIP, DIAMOND have no native MultiQC parser.
    //                   Author custom-content modules post-run with the nf-multiqc skill; do not fabricate here.

    //
    // Collate and save software versions (topic-style versions are collected automatically below)
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name:  'phinder_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        )

    //
    // MODULE: MultiQC (native-supported reports only)
    //
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    def ch_summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    def ch_multiqc_custom_methods_description = multiqc_methods_description
        ? file(multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/methods_description_template.yml", checkIfExists: true)
    def ch_methods_description = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))
    MULTIQC(
        ch_multiqc_files.flatten().collect().map { files ->
            [
                [id: 'phinder'],
                files,
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )

    emit:
    multiqc_report = MULTIQC.out.report.map { _meta, report -> [report] }.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                                                   // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
