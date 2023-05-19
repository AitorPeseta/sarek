//
// merge samples with genomicsdbimport, perform joint genotyping with genotypeGVCFS
include { BCFTOOLS_SORT                                                      } from '../../../modules/nf-core/bcftools/sort/main'
include { SENTIEON_APPLYVQSR as SENTIEON_APPLYVQSR_INDEL                     } from '../../../modules/local/sentieon/applyvarcal/main'
include { SENTIEON_APPLYVQSR as SENTIEON_APPLYVQSR_SNP                       } from '../../../modules/local/sentieon/applyvarcal/main'
include { SENTIEON_JOINT_GENOTYPING                                          } from '../../../modules/local/sentieon/genotyper/main'
include { GATK4_MERGEVCFS as MERGE_GENOTYPEGVCFS                             } from '../../../modules/nf-core/gatk4/mergevcfs/main'
include { GATK4_MERGEVCFS as MERGE_VQSR                                      } from '../../../modules/nf-core/gatk4/mergevcfs/main'
include { SENTIEON_VARIANTRECALIBRATOR as SENTIEON_VARIANTRECALIBRATOR_INDEL } from '../../../modules/local/sentieon/varcal/main'   // Temporary hack
include { SENTIEON_VARIANTRECALIBRATOR as SENTIEON_VARIANTRECALIBRATOR_SNP   } from '../../../modules/local/sentieon/varcal/main'   // Temporary hack

workflow BAM_JOINT_CALLING_GERMLINE_SENTIEON {
    take:
    input                // channel: [ meta, [ input ], [ input_index ], intervals ]
    fasta                // channel: [ fasta ]
    fai                  // channel: [ fasta_fai ]
    dict                 // channel: [ dict ]
    dbsnp
    dbsnp_tbi
    dbsnp_vqsr
    resource_indels_vcf
    resource_indels_tbi
    known_indels_vqsr
    resource_snps_vcf
    resource_snps_tbi
    known_snps_vqsr

    main:
    versions = Channel.empty()

    sentieon_input = input
        .map{ meta, gvcf, tbi, intervals -> [ [ id:'joint_variant_calling', intervals_name:intervals.simpleName, num_intervals:meta.num_intervals ], gvcf, tbi, intervals ] }
        .groupTuple(by:[0, 3])

    SENTIEON_JOINT_GENOTYPING(sentieon_input, fasta, fai)

    // TO-DO: Try to use a much functionality from Sentieon as possible. Sentieon should have a function for merging vfcs.
    BCFTOOLS_SORT(SENTIEON_JOINT_GENOTYPING.out.vcf_gz)

    gvcf_to_merge = BCFTOOLS_SORT.out.vcf.map{ meta, vcf -> [ meta.subMap('num_intervals') + [ id:'joint_variant_calling', patient:'all_samples', variantcaller:'sentieon_haplotyper' ], vcf ]}.groupTuple()

    // Merge scatter/gather vcfs & index
    // Rework meta for variantscalled.csv and annotation tools
    MERGE_GENOTYPEGVCFS(gvcf_to_merge, dict.map{ it -> [ [ id:'dict' ], it ] } )

    vqsr_input = MERGE_GENOTYPEGVCFS.out.vcf.join(MERGE_GENOTYPEGVCFS.out.tbi, failOnDuplicate: true)
    indels_resource_label = known_indels_vqsr.mix(dbsnp_vqsr).collect()
    snps_resource_label = known_snps_vqsr.mix(dbsnp_vqsr).collect()

    // Recalibrate INDELs and SNPs separately
    SENTIEON_VARIANTRECALIBRATOR_INDEL(
        vqsr_input,
        resource_indels_vcf,
        resource_indels_tbi,
        indels_resource_label,
        fasta,
        fai,
        dict)

    SENTIEON_VARIANTRECALIBRATOR_SNP(
        vqsr_input,
        resource_snps_vcf,
        resource_snps_tbi,
        snps_resource_label,
        fasta,
        fai,
        dict)

    //Prepare INDELs and SNPs separately for ApplyVQSR

    // Join results of variant recalibration into a single channel tuple
    // Rework meta for variantscalled.csv and annotation tools
    temp_vqsr_input_snp = vqsr_input.join(SENTIEON_VARIANTRECALIBRATOR_SNP.out.recal, failOnDuplicate: true)
        .join(SENTIEON_VARIANTRECALIBRATOR_SNP.out.idx, failOnDuplicate: true)
        .join(SENTIEON_VARIANTRECALIBRATOR_SNP.out.tranches, failOnDuplicate: true)
        .map{ meta, vcf, tbi, recal, index, tranche -> [ meta - meta.subMap('id') + [ id:'recalibrated_joint_variant_calling' ], vcf, tbi, recal, index, tranche ] }

    // Join results of variant recalibration into a single channel tuple
    // Rework meta for variantscalled.csv and annotation tools
    temp_vqsr_input_indel = vqsr_input.join(SENTIEON_VARIANTRECALIBRATOR_INDEL.out.recal, failOnDuplicate: true)
        .join(SENTIEON_VARIANTRECALIBRATOR_INDEL.out.idx, failOnDuplicate: true)
        .join(SENTIEON_VARIANTRECALIBRATOR_INDEL.out.tranches, failOnDuplicate: true)
        .map{ meta, vcf, tbi, recal, index, tranche -> [ meta - meta.subMap('id') + [ id:'recalibrated_joint_variant_calling' ], vcf, tbi, recal, index, tranche ] }


    SENTIEON_APPLYVQSR_SNP(
        temp_vqsr_input_snp,
        fasta,
        fai,
        dict)

    SENTIEON_APPLYVQSR_INDEL(
        temp_vqsr_input_indel,
        fasta,
        fai,
        dict)

    vqsr_snp_vcf = SENTIEON_APPLYVQSR_SNP.out.vcf
    vqsr_indel_vcf = SENTIEON_APPLYVQSR_INDEL.out.vcf

    //Merge VQSR outputs into final VCF
    MERGE_VQSR(
        vqsr_snp_vcf.mix(vqsr_indel_vcf).groupTuple(),
        dict.map{ it -> [ [ id:'dict' ], it ] }
    )

    genotype_vcf   = MERGE_GENOTYPEGVCFS.out.vcf.mix(MERGE_VQSR.out.vcf)
    genotype_index = MERGE_GENOTYPEGVCFS.out.tbi.mix(MERGE_VQSR.out.tbi)

    versions = versions.mix(SENTIEON_JOINT_GENOTYPING.out.versions)
    versions = versions.mix(SENTIEON_VARIANTRECALIBRATOR_SNP.out.versions)
    versions = versions.mix(SENTIEON_VARIANTRECALIBRATOR_INDEL.out.versions)
    versions = versions.mix(SENTIEON_APPLYVQSR_INDEL.out.versions)

    emit:
    genotype_index  // channel: [ val(meta), [ tbi ] ]
    genotype_vcf    // channel: [ val(meta), [ vcf ] ]

    versions        // channel: [ versions.yml ]
}
