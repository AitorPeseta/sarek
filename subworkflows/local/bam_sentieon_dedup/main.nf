//
// SENTIEON DEDUP
//
// For all modules here:
// A when clause condition is defined in the conf/modules.config to determine if the module should be run

include { CRAM_QC_MOSDEPTH_SAMTOOLS              } from '../cram_qc_mosdepth_samtools/main'
include { GATK4_MARKDUPLICATES                   } from '../../../modules/nf-core/gatk4/markduplicates/main'
include { SENTIEON_DEDUP                         } from '../../../modules/nf-core/sentieon/dedup/main'
include { SAMTOOLS_INDEX as INDEX_INPUT          } from '../../../modules/nf-core/samtools/index/main'
include { SAMTOOLS_INDEX as INDEX_DEDUPED        } from '../../../modules/nf-core/samtools/index/main'
include { SAMTOOLS_INDEX as INDEX_MARKDUPLICATES } from '../../../modules/nf-core/samtools/index/main'

workflow BAM_SENTIEON_DEDUP {
    take:
    bam                    // channel: [mandatory] [ meta, bam ]  // Although the channel is named "bam", it may contain cram-files.
    fasta                  // channel: [mandatory] [ fasta ]
    fasta_fai              // channel: [mandatory] [ fasta_fai ]
    intervals_bed_combined // channel: [optional]  [ intervals_bed ]

    main:
    versions = Channel.empty()
    reports  = Channel.empty()

    INDEX_INPUT(bam)
    bam_bai = bam.join(INDEX_INPUT.out.bai.concat(INDEX_INPUT.out.crai)) // This is done since if the "bam" channel contains cram-files, then the index files will be in the channel INDEX_INPUT.out.crai and not in INDEX_INPUT.out.bai
    SENTIEON_DEDUP(bam_bai, fasta, fasta_fai)

    INDEX_DEDUPED(SENTIEON_DEDUP.out.cram)

    // Join with the crai file
    cram = SENTIEON_DEDUP.out.cram.join(INDEX_DEDUPED.out.crai, failOnDuplicate: true, failOnMismatch: true)

    // QC on CRAM
    CRAM_QC_MOSDEPTH_SAMTOOLS(cram, fasta, intervals_bed_combined)

    // Gather all reports generated
    reports = reports.mix(SENTIEON_DEDUP.out.metrics)
    reports = reports.mix(SENTIEON_DEDUP.out.score)
    reports = reports.mix(CRAM_QC_MOSDEPTH_SAMTOOLS.out.reports)

    // Gather versions of all tools used
    versions = versions.mix(SENTIEON_DEDUP.out.versions)
    versions = versions.mix(INDEX_DEDUPED.out.versions)
    versions = versions.mix(CRAM_QC_MOSDEPTH_SAMTOOLS.out.versions)

    emit:
    cram
    reports

    versions    // channel: [ versions.yml ]
}
