include { initOptions; saveFiles; getSoftwareName } from './functions'

params.options = [:]
def options    = initOptions(params.options)

environment = params.enable_conda ? "bioconda::qualimap=2.2.2d" : null
container = "quay.io/biocontainers/qualimap:2.2.2d--1"
if (workflow.containerEngine == 'singularity' && !params.pull_docker_container) container = "https://depot.galaxyproject.org/singularity/qualimap:2.2.2d--1"

process QUALIMAP_BAMQC {
    label 'memory_max'
    label 'cpus_16'

    tag "${meta.id}"

    publishDir params.outdir, mode: params.publish_dir_mode,
        saveAs: { filename -> saveFiles(filename:filename, options:params.options, publish_dir:getSoftwareName(task.process), publish_id:meta.id) }

    conda environment
    container container

    input:
         tuple val(meta), path(bam)
         path(target_bed)

     output:
         path("${bam.baseName}") 

     script:
     use_bed = params.target_bed ? "-gff ${target_bed}" : ''
     """
     qualimap --java-mem-size=${task.memory.toGiga()}G \
        bamqc \
        -bam ${bam} \
        --paint-chromosome-limits \
        --genome-gc-distr HUMAN \
        ${use_bed} \
        -nt ${task.cpus} \
        -skip-duplicated \
        --skip-dup-mode 0 \
        -outdir ${bam.baseName} \
        -outformat HTML
     """
}
