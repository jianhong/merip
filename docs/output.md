# jianhong/merip: Output

## Introduction

This document describes the output produced by the pipeline. Most of the plots are taken from the MultiQC report, which summarises results at the end of the pipeline.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data using the following steps:

- [FastQC](#fastqc) - Raw and trimmed read QC
- [fastp](#fastp) - Trim process QC
- [Alignment](#alignment) - Alignment bams, bigwigs, and featurecounts if spikin fasta file is provided
- [MACS2](#macs2) - Peak calling output
- [Aggregate analysis](#aggregate-analysis) - Aggregate analysis by DeepTools
- [MultiQC](#multiqc) - Aggregate report describing results and QC from the whole pipeline
- [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution

### FastQC

<details markdown="1">
<summary>Output files</summary>

- `QC/fastqc/[raw|trim]/`
  - `*_fastqc.html`: FastQC report containing quality metrics.
  - `*_fastqc.zip`: Zip archive containing the FastQC report, tab-delimited data file and plot images.

</details>

[FastQC](http://www.bioinformatics.babraham.ac.uk/projects/fastqc/) gives general quality metrics about your sequenced reads. It provides information about the quality score distribution across your reads, per base sequence content (%A/T/G/C), adapter contamination and overrepresented sequences. For further reading and documentation see the [FastQC help pages](http://www.bioinformatics.babraham.ac.uk/projects/fastqc/Help/).

![MultiQC - FastQC sequence counts plot](images/mqc_fastqc_counts.png)

![MultiQC - FastQC mean quality scores plot](images/mqc_fastqc_quality.png)

![MultiQC - FastQC adapter content plot](images/mqc_fastqc_adapter.png)

> **NB:** The FastQC plots displayed in the MultiQC report shows _untrimmed_ reads. They may contain adapter sequence and potentially regions with low quality.

### fastp

<details markdown="1">
<summary>Output files</summary>

- `QC/fastp/`
  - `*.fastp.html`: FastP report containing quality metrics.

</details>

[fastp](https://github.com/OpenGene/fastp) is a tool designed to provide fast all-in-one preprocessing for FastQ files. It is used to trim the fastq files.

### Alignment

The pipeline has been written in a way where all the files generated downstream of the alignment are placed in the same directory as specified by `--aligner` e.g. if `--aligner bwa` is specified then all the downstream results will be placed in the `alignments/bwa/` directory. This helps with organising the directory structure and more importantly, allows the end-user to get the results from multiple aligners by simply re-running the pipeline with a different `--aligner` option along the `-resume` parameter. It also means that results won't be overwritten when resuming the pipeline and can be used for benchmarking between alignment algorithms if required. Thus, `<ALIGNER>` in the directory structure below corresponds to the aligner set when running the pipeline.

<details markdown="1">
    <summary>Output files</summary>

- `alignments/<ALIGNER>/`
  - `sorted_bam/*.bam`: The files resulting from the alignment of individual libraries are not saved by default so this directory will not be present in your results. You can override this behaviour with the use of the `--save_align_intermeds` flag in which case it will contain the coordinate sorted alignment files in [`*.bam`](https://samtools.github.io/hts-specs/SAMv1.pdf) format.
  - `bigwig/*.bigWig`: The bigWig files generated by deeptools by `CPM` normalization.
  - `featurecounts_spikein/*`: The featurecounts output for genes including the spikeins.
- `QC/alignments/<ALIGNER>/`
  - `<SAMPLE>.sorted.bam.flagstat`, `<SAMPLE>.sorted.bam.idxstats` and `<SAMPLE>.sorted.bam.stats` files generated from the alignment files.

> **NB:** File names in the resulting directory (i.e. `<ALIGNER>/library/`) will have the '`.Lb.`' suffix.

</details>

Adapter-trimmed reads are mapped to the reference assembly using the aligner set by the `--aligner` parameter. Available aligners are [BWA](http://bio-bwa.sourceforge.net/bwa.shtml) (default), [Bowtie 2](http://bowtie-bio.sourceforge.net/bowtie2/index.shtml), [HISAT2](http://daehwankimlab.github.io/hisat2/) and [STAR](https://github.com/alexdobin/STAR). A genome index is required to run any of this aligners so if this is not provided explicitly using the corresponding parameter (e.g. `--bwa_index`), then it will be created automatically from the genome fasta input. The index creation process can take a while for larger genomes so it is possible to use the `--save_reference` parameter to save the indices for future pipeline runs, reducing processing times.

### MACS2

<details markdown="1">
    <summary>Output files</summary>

- `called_peaks/macs2_<ALIGNER>/`
  - `*.xls`, `*.broadPeak` or `*.narrowPeak`, `*.gappedPeak`, `*summits.bed`: MACS2 output files.
  - `anno/*.anno.csv`: ChIPpeakAnno peak-to-gene annotation file.
- `QC/macs2_<ALIGNER>/`
  - `anno/*.png`: QC plots for MACS2 peaks.
  - `*.FRiP_mqc.tsv`, `*.peak_count_mqc.tsv`: MultiQC custom-content files for FRiP score, peak count and peak-to-gene ratios.

</details>

[MACS2](https://github.com/macs3-project/MACS) is one of the most popular peak-calling algorithms for ChIP-seq data. By default, the peaks are called with the MACS2 `--nomodel --extsize 50 -B --scale-to small --keep-dup 5` parameter. See [MACS2 outputs](https://github.com/macs3-project/MACS/blob/master/docs/callpeak.md#output-files) for a description of the output files generated by MACS2.


[ChIPpeakAnno](https://bioconductor.org/packages/release/bioc/html/ChIPpeakAnno.html) is used to annotate the peaks relative to known genomic features.

Various QC plots per sample including number of peaks, fold-change distribution, [FRiP score](https://genome.cshlp.org/content/22/9/1813.full.pdf+html) and peak-to-gene feature annotation are also generated by the pipeline. Where possible these have been integrated into the MultiQC report.

### Aggregate analysis

Present QC for the raw read, alignment, and peak results

<details markdown="1">
    <summary>Output files</summary>

- `QC/deeptools_<ALIGNER>/genebody_ups_dws_profile`
  - `*.computeMatrix.*`: Outputs of deepTools computeMatrix
  - `*.plotHeatmap.*`: Outputs of deepTools plotHeatmap.
  - `*.plotProfile.*`: Outputs of deepTools plotProfile.

</details>

[DeepTools](https://deeptools.readthedocs.io/en/develop/) is a collection of tools for exploring deep sequencing data. The outputs will show the aggregate analysis for upstream 3K to downstream 3K coverage of genes.

### MultiQC

<details markdown="1">
<summary>Output files</summary>

- `QC/multiqc/`
  - `multiqc_report.html`: a standalone HTML file that can be viewed in your web browser.
  - `multiqc_data/`: directory containing parsed statistics from the different tools used in the pipeline.
  - `multiqc_plots/`: directory containing static images from the report in various formats.

</details>

[MultiQC](http://multiqc.info) is a visualization tool that generates a single HTML report summarising all samples in your project. Most of the pipeline QC results are visualised in the report and further statistics are available in the report data directory.

Results generated by MultiQC collate pipeline QC from supported tools e.g. FastQC. The pipeline has special steps which also allow the software versions to be reported in the MultiQC output for future traceability. For more information about how to use MultiQC reports, see <http://multiqc.info>.

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow: `execution_report.html`, `execution_timeline.html`, `execution_trace.txt` and `pipeline_dag.dot`/`pipeline_dag.svg`.
  - Reports generated by the pipeline: `pipeline_report.html`, `pipeline_report.txt` and `software_versions.yml`. The `pipeline_report*` files will only be present if the `--email` / `--email_on_fail` parameter's are used when running the pipeline.
  - Reformatted samplesheet files used as input to the pipeline: `samplesheet.valid.csv`.

</details>

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
