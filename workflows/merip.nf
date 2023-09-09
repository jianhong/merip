/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PRINT PARAMS SUMMARY
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { paramsSummaryLog; paramsSummaryMap; fromSamplesheet } from 'plugin/nf-validation'

def logo = NfcoreTemplate.logo(workflow, params.monochrome_logs)
def citation = '\n' + WorkflowMain.citation(workflow) + '\n'
def summary_params = paramsSummaryMap(workflow)

// Print parameter summary log to screen
log.info logo + paramsSummaryLog(workflow) + citation

WorkflowMerip.initialise(params, log)

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    VALIDATE INPUTS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Check rRNA databases for sortmerna
if (params.remove_ribo_rna) {
    ch_ribo_db = file(params.ribo_database_manifest)
    if (ch_ribo_db.isEmpty()) {exit 1, "File provided with --ribo_database_manifest is empty: ${ch_ribo_db.getName()}!"}
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    CONFIG FILES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

ch_multiqc_config          = Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
ch_multiqc_custom_config   = params.multiqc_config ? Channel.fromPath( params.multiqc_config, checkIfExists: true ) : Channel.empty()
ch_multiqc_logo            = params.multiqc_logo   ? Channel.fromPath( params.multiqc_logo, checkIfExists: true ) : Channel.empty()
ch_multiqc_custom_methods_description = params.multiqc_methods_description ? file(params.multiqc_methods_description, checkIfExists: true) : file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT LOCAL MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: local modules
//
include { FRIP_SCORE                  } from '../modules/local/frip_score'
include { MULTIQC_CUSTOM_PEAKS        } from '../modules/local/multiqc_custom_peaks'

//
// SUBWORKFLOW: Consisting of a mix of local and nf-core/modules
//
include { PREPARE_GENOME              } from '../subworkflows/local/prepare_genome'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT NF-CORE MODULES/SUBWORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

//
// MODULE: Installed directly from nf-core/modules
//
include { CAT_FASTQ                   } from '../modules/nf-core/cat/fastq/main'
//include { FASTQC                      } from '../modules/nf-core/fastqc/main'
include { MULTIQC                     } from '../modules/nf-core/multiqc/main'
include { SORTMERNA                   } from '../modules/nf-core/sortmerna/main'
include { CUSTOM_DUMPSOFTWAREVERSIONS } from '../modules/nf-core/custom/dumpsoftwareversions/main'
include { BEDTOOLS_GENOMECOV          } from '../modules/nf-core/bedtools/genomecov/main'
include { BEDTOOLS_SORT               } from '../modules/nf-core/bedtools/sort/main'
include { UCSC_BEDGRAPHTOBIGWIG       } from '../modules/nf-core/ucsc/bedgraphtobigwig/main'
include { DEEPTOOLS_COMPUTEMATRIX     } from '../modules/nf-core/deeptools/computematrix/main'
include { DEEPTOOLS_PLOTPROFILE       } from '../modules/nf-core/deeptools/plotprofile/main'
include { DEEPTOOLS_PLOTHEATMAP       } from '../modules/nf-core/deeptools/plotheatmap/main'
include { DEEPTOOLS_PLOTFINGERPRINT   } from '../modules/nf-core/deeptools/plotfingerprint/main'
include { MACS2_CALLPEAK              } from '../modules/nf-core/macs2/callpeak/main'

//
// SUBWORKFLOW: Installed directly from nf-core/modules
//
include { FASTQ_TRIM_FASTP_FASTQC     } from '../subworkflows/nf-core/fastq_trim_fastp_fastqc/main'
include { FASTQ_ALIGN_STAR            } from '../subworkflows/nf-core/fastq_align_star/main'
include { FASTQ_ALIGN_HISAT2          } from '../subworkflows/nf-core/fastq_align_hisat2/main'
include { FASTQ_ALIGN_BOWTIE2         } from '../subworkflows/nf-core/fastq_align_bowtie2/main'
include { FASTQ_ALIGN_BWA             } from '../subworkflows/nf-core/fastq_align_bwa/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Info required for completion email and summary
def multiqc_report = []

workflow MERIP {

    ch_versions = Channel.empty()

    //
    // SUBWORKFLOW: Read in samplesheet, validate and stage input files
    //
    Channel
        .fromSamplesheet("input")
        .map {
            meta, fastq_1, fastq_2 ->
                if (!fastq_2) {
                    return [ meta.id, meta + [ single_end:true ], [ fastq_1 ] ]
                } else {
                    return [ meta.id, meta + [ single_end:false ], [ fastq_1, fastq_2 ] ]
                }
        }
        .groupTuple()
        .map { [it[1][0], it[2]] }
        .branch {
            meta, fastqs ->
                single  : fastqs.size() == 1
                    return [ meta, fastqs.flatten() ]
                multiple: fastqs.size() > 1
                    return [ meta, fastqs.flatten() ]
        }
        .set { ch_fastq }
    ch_fastq.single.view()
    ch_fastq.multiple.view()

    //
    // MODULE: Concatenate FastQ files from same sample if required
    //
    CAT_FASTQ (
        ch_fastq.multiple
    )
    .reads
    .mix(ch_fastq.single)
    .set { ch_cat_fastq }
    // ch_versions = ch_versions.mix(CAT_FASTQ.out.versions.first().ifEmpty(null)) // not work, bug

    //
    // MODULE: Run FastP
    //
    FASTQ_TRIM_FASTP_FASTQC (
        ch_cat_fastq,
        params.adapter_fasta ? Channel.value(file(params.adapter_fasta)): null,
        params.save_trimmed_fail,
        params.save_merged,
        params.skip_fastp,
        params.skip_fastqc
    )
    ch_versions = ch_versions.mix(FASTQC.out.versions.first())

    //
    // WORKFLOW: prepare genome
    //
    PREPARE_GENOME ()
    ch_versions = ch_versions.mix(PREPARE_GENOME.out.versions)

    //
    // MODULE: Remove ribosomal RNA reads
    //
    ch_sortmerna_multiqc = Channel.empty()
    if (params.remove_ribo_rna) {
        ch_sortmerna_fastas = Channel.from(ch_ribo_db.readLines()).map { row -> file(row, checkIfExists: true) }.collect()

        SORTMERNA (
            FASTQ_TRIM_FASTP_FASTQC.out.reads,
            ch_sortmerna_fastas
        )
        .reads
        .set { ch_filtered_reads }

        ch_sortmerna_multiqc = SORTMERNA.out.log
        ch_versions = ch_versions.mix(SORTMERNA.out.versions.first())
    }else{
        ch_filtered_reads = FASTQ_TRIM_FASTP_FASTQC.out.reads
    }

    //
    // WORKFLOW: Mapping reads
    //
    switch( params.aligner ){ // "star", "hisat2", "bwa", "bowtie2"
        case "star":
            FASTQ_ALIGN_STAR(
                ch_filtered_reads,
                PREPARE_GENOME.out.star_index.map{ [ [:], it ] },
                PREPARE_GENOME.out.gtf.map{ [ [:], it ] },
                params.star_ignore_sjdbgtf,
                params.seq_platform,
                params.seq_center,
                PREPARE_GENOME.out.fasta.map { [ [:], it ] }
            )
            ch_bam_bai = FASTQ_ALIGN_STAR.out.bam.join(FASTQ_ALIGN_STAR.out.bai, by: [0])
            ch_bam_mqc = FASTQ_ALIGN_STAR.out.stats.collect{it[1]}.ifEmpty(null)
            ch_bam_mqc = ch_bam_mqc.mix( FASTQ_ALIGN_STAR.out.flagstat.collect{it[1]}.ifEmpty(null) )
            ch_bam_mqc = ch_bam_mqc.mix( FASTQ_ALIGN_STAR.out.idxstats.collect{it[1]}.ifEmpty(null) )
            break
        case "hisat2":
            FASTQ_ALIGN_HISAT2(
                ch_filtered_reads,
                PREPARE_GENOME.out.hisat2_index,
                PREPARE_GENOME.out.splicesites,
                PREPARE_GENOME.out.fasta
            )
            ch_bam_bai = FASTQ_ALIGN_STAR.out.bam.join(FASTQ_ALIGN_STAR.out.bai, by: [0])
            ch_bam_mqc = FASTQ_ALIGN_STAR.out.stats.collect{it[1]}.ifEmpty(null)
            ch_bam_mqc = ch_bam_mqc.mix( FASTQ_ALIGN_STAR.out.flagstat.collect{it[1]}.ifEmpty(null) )
            ch_bam_mqc = ch_bam_mqc.mix( FASTQ_ALIGN_STAR.out.idxstats.collect{it[1]}.ifEmpty(null) )
            break
        case "bwa" :
            FASTQ_ALIGN_BWA(
                ch_filtered_reads,
                PREPARE_GENOME.out.bwa_index,
                true,
                PREPARE_GENOME.out.fasta.map { [ [:], it ] }
            )
            ch_bam_bai = FASTQ_ALIGN_STAR.out.bam.join(FASTQ_ALIGN_STAR.out.bai, by: [0])
            ch_bam_mqc = FASTQ_ALIGN_STAR.out.stats.collect{it[1]}.ifEmpty(null)
            ch_bam_mqc = ch_bam_mqc.mix( FASTQ_ALIGN_STAR.out.flagstat.collect{it[1]}.ifEmpty(null) )
            ch_bam_mqc = ch_bam_mqc.mix( FASTQ_ALIGN_STAR.out.idxstats.collect{it[1]}.ifEmpty(null) )
            break
        case "bowtie2" :
            FASTQ_ALIGN_BOWTIE2(
                ch_filtered_reads,
                PREPARE_GENOME.out.bowtie2_index,
                false,
                true,
                PREPARE_GENOME.out.fasta
            )
            ch_bam_bai = FASTQ_ALIGN_STAR.out.bam.join(FASTQ_ALIGN_STAR.out.bai, by: [0])
            ch_bam_mqc = FASTQ_ALIGN_STAR.out.stats.collect{it[1]}.ifEmpty(null)
            ch_bam_mqc = ch_bam_mqc.mix( FASTQ_ALIGN_STAR.out.flagstat.collect{it[1]}.ifEmpty(null) )
            ch_bam_mqc = ch_bam_mqc.mix( FASTQ_ALIGN_STAR.out.idxstats.collect{it[1]}.ifEmpty(null) )
            break
    }


    //
    // MODULE: BedGraph coverage tracks: scale factor -> genomecov -> sort -> bedgraphtobigwig
    //

    //
    // MODULE: deepTools profile: computematrix -> plotprofile -> plotheatmap
    //
    if (!params.skip_plot_profile) {

    }

    //
    // MODULE: Peak calling and QC
    //
    ch_bam_bai
        .map{
            meta, bam, bai ->
                meta.control ? null : [ meta.id, [ bam ] , [ bai ] ]
        }.set { ch_control_bam_bai }

    ch_bam_bai
        .map{
            meta, bam, bai ->
                meta.control ? [ meta.control, meta, [ bam ] , [ bai ] ] : null
        }
        .combine(ch_control_bam_bai, by:0)
        .map { [ it[1] , it[2] + it[4], it[3] + it[5] ] }
        .set { ch_ip_control_bam_bai }

    //
    // MODULE: deepTools plotFingerprint joint QC for IP and control
    //
    ch_deeptoolsplotfingerprint_multiqc = Channel.empty()
    if (!params.skip_plot_fingerprint) {
        DEEPTOOLS_PLOTFINGERPRINT (
            ch_ip_control_bam_bai
        )
        ch_deeptoolsplotfingerprint_multiqc = DEEPTOOLS_PLOTFINGERPRINT.out.matrix
        ch_versions = ch_versions.mix(DEEPTOOLS_PLOTFINGERPRINT.out.versions.first())
    }

    //
    // MODULE: Peak calling by MACS2
    //
    ch_ip_control_bam_bai
        .map {
            meta, bams, bais ->
                [ meta , bams[0], bams[1] ]
        }
        .set { ch_ip_control_bam }

    MACS2_CALLPEAK (
        ch_ip_control_bam,
        PREPARE_GENOME.out.macs_gsize
    )
    ch_versions = ch_versions.mix(MACS2_CALLPEAK.out.versions.first())

    //
    // Filter out samples with 0 MACS2 peaks called
    //
    MACS2_CALLPEAK
        .out
        .peak
        .filter {
            meta, peaks ->
                peaks.size() > 0
        }
        .set { ch_macs2_peaks }

    // Create channels: [ meta, ip_bam, peaks ]
    ch_ip_control_bam
        .join(ch_macs2_peaks, by: [0])
        .map {
            it ->
                [ it[0], it[1], it[3] ]
        }
        .set { ch_ip_bam_peaks }

    //
    // MODULE: Calculate FRiP score
    //
    FRIP_SCORE (
        ch_ip_bam_peaks
    )
    ch_versions = ch_versions.mix(FRIP_SCORE.out.versions.first())
    // Create channels: [ meta, peaks, frip ]
    ch_ip_bam_peaks
        .join(FRIP_SCORE.out.txt, by: [0])
        .map {
            it ->
                [ it[0], it[2], it[3] ]
        }
        .set { ch_ip_peaks_frip }

    //
    // MODULE: FRiP score custom content for MultiQC
    //
    MULTIQC_CUSTOM_PEAKS (
        ch_ip_peaks_frip,
        ch_peak_count_header,
        ch_frip_score_header
    )


    //
    // prepare the software version yaml files
    //
    CUSTOM_DUMPSOFTWAREVERSIONS (
        ch_versions.unique().collectFile(name: 'collated_versions.yml')
    )

    //
    // MODULE: MultiQC
    //
    workflow_summary    = WorkflowMerip.paramsSummaryMultiqc(workflow, summary_params)
    ch_workflow_summary = Channel.value(workflow_summary)

    methods_description    = WorkflowMerip.methodsDescriptionText(workflow, ch_multiqc_custom_methods_description, params)
    ch_methods_description = Channel.value(methods_description)

    ch_multiqc_files = Channel.empty()
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml'))
    ch_multiqc_files = ch_multiqc_files.mix(CUSTOM_DUMPSOFTWAREVERSIONS.out.mqc_yml.collect())
    //ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{it[1]}.ifEmpty([]))
    ch_multiqc_files = ch_multiqc_files.mix(FASTQ_TRIM_FASTP_FASTQC.out.fastqc_raw_zip.collect{it[1]}.ifEmpty())
    ch_multiqc_files = ch_multiqc_files.mix(FASTQ_TRIM_FASTP_FASTQC.out.fastqc_trim_zip.collect{it[1]}.ifEmpty())
    ch_multiqc_files = ch_multiqc_files.mix(MULTIQC_CUSTOM_PEAKS.out.count.collect{it[1]}.ifEmpty())
    ch_multiqc_files = ch_multiqc_files.mix(MULTIQC_CUSTOM_PEAKS.out.frip.collect{it[1]}.ifEmpty())


    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList()
    )
    multiqc_report = MULTIQC.out.report.toList()
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    COMPLETION EMAIL AND SUMMARY
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow.onComplete {
    if (params.email || params.email_on_fail) {
        NfcoreTemplate.email(workflow, params, summary_params, projectDir, log, multiqc_report)
    }
    NfcoreTemplate.summary(workflow, params, log)
    if (params.hook_url) {
        NfcoreTemplate.IM_notification(workflow, params, summary_params, projectDir, log)
    }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/