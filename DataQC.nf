def helpMessage() {
    log.info"""
    =======================================================
     DataQC v${workflow.manifest.version}
    =======================================================
    Usage:
    The typical command for running the pipeline is as follows:
    nextflow run DataQC.nf \
        --bfile EstBB_HT12v3\
        --expfile EstBB_HT12v3_exp.txt\
        --gte gte_EstBB_HT12v3.txt\
        --exp_platform HT12v3\
        --cohort_name EstBB_HT12v3\
        --outdir EstBB_HT12v3_PreImputationQCd\
        -profile slurm\
        -resume

    Mandatory arguments:
      --cohort_name                 Name of the cohort.
      --bfile                       Path to the unimputed genotype files in plink bed/bim/fam format (without extensions bed/bim/fam).
      --expfile                     Path to the un-preprocessed gene expression matrix (genes/probes in the rows, samples in the columns). Can be from RNA-seq experiment or from array. NB! For Affymetrix arrays (AffyU219, AffyExon) we assume that standard preprocessing and normalisation is already done.
      --gte                         Genotype-to-expression linking file. Tab-delimited, no header. First column: sample ID for genotype data. Second column: corresponding sample ID for gene expression data. Can be used to filter samples from the analysis.
      --exp_platform                Indicator indicating the gene expression platform. HT12v3, HT12v4, HuRef8, RNAseq, AffyU219, AffyHumanExon.
      --outdir                      Path to the output directory.
      --GenOutThresh                "Outlierness" score threshold for excluding ethnic outliers. Defaults to 0.4 but should be adjusted according to visual inspection.
      --GenSdThresh                 Threshold for declaring samples outliers based on genetic PC1 and PC2. Defaults to 3 SD from the mean of PC1 and PC2 but should be adjusted according to visual inspection.
      --ExpSdThresh                 Standard deviation threshold for excluding gene expression outliers. By default, samples away by 3 SDs from the mean of PC1 are removed.
      --ContaminationArea           Area that marks likely contaminated samples based on sex chromosome gene expression. Must be an angle between 0 and 90. The angle represents the total area around the y = x function.
 
    Optional arguments
      --pruned_variants_sex_check   Path to a plink ranges file that defines which variants to use for the check-sex command. Use this when the automatic selection does not yield satisfactory results.
      --InclusionList               File with sample IDs to restrict to the analysis. Useful for keeping in the inclusion list of the samples. By default, all samples are kept.
      --ExclusionList               File with sample IDs to remove from the analysis. Useful for removing the ancestry outliers or restricting the genotype data to one superpopulation. Samples are also removed from the inclusion list. By default, all samples are kept.

    """.stripIndent()
}

// Define location of Report_template.Rmd
params.report_template = "$baseDir/bin/Report_template.Rmd"


// Define input channels
Channel
    .from(params.bfile)
    .map { study -> [file("${study}.bed"), file("${study}.bim"), file("${study}.fam")]}
    .ifEmpty { exit 1, "Input genotype files not found!" }
    .set { bfile_ch }

Channel
    .from(params.expfile)
    .map { study -> [file("${study}")]}
    .ifEmpty { exit 1, "Input expression files not found!" }
    .set { expfile_ch }

Channel
    .from(params.gte)
    .map { study -> [file("${study}")]}
    .ifEmpty { exit 1, "Input GTE file not found!" }
    .into { gte_ch_gen; gte_ch_exp }

Channel
    .fromPath(params.report_template)
    .ifEmpty { exit 1, "Input report not found!" }
    .set { report_ch }


params.GenOutThresh = 0.4
params.GenSdThresh = 3
params.ExpSdThresh = 4
params.ContaminationArea = 30
params.exp_platform = ''
params.cohort_name = ''
params.outdir = ''

params.InclusionList = ''
params.ExclusionList = ''

params.pruned_variants_sex_check = ''

// Header log info
log.info """=======================================================
DataQC v${workflow.manifest.version}"
======================================================="""
def summary = [:]
summary['Pipeline Name']            = 'DataQC'
summary['Pipeline Version']         = workflow.manifest.version
summary['PLINK bfile']              = params.bfile
summary['S threshold']              = params.GenOutThresh
summary['Gen SD threshold']         = params.GenSdThresh
summary['Exp SD threshold']         = params.ExpSdThresh
summary['Contamination area']       = params.ContaminationArea
summary['Expression matrix']        = params.expfile
summary['GTE file']                 = params.gte
summary['Max Memory']               = params.max_memory
summary['Max CPUs']                 = params.max_cpus
summary['Max Time']                 = params.max_time
summary['Cohort name']              = params.cohort_name
if(params.pruned_variants_sex_check) summary['Pruned variants for sex check'] = params.pruned_variants_sex_check
if(params.InclusionList) summary['Inclusion list'] = params.InclusionList
if(params.ExclusionList) summary['Exclusion list'] = params.ExclusionList
summary['Expression platform']      = params.exp_platform
summary['Output dir']               = params.outdir
summary['Working dir']              = workflow.workDir
summary['Container Engine']         = workflow.containerEngine
if(workflow.containerEngine) summary['Container'] = workflow.container
summary['Current home']             = "$HOME"
summary['Current user']             = "$USER"
summary['Current path']             = "$PWD"
summary['Working dir']              = workflow.workDir
summary['Script dir']               = workflow.projectDir
summary['Config Profile']           = workflow.profile
log.info summary.collect { k,v -> "${k.padRight(21)}: $v" }.join("\n")
log.info "========================================="

process GenotypeQC {

    tag {GenotypeQC}

    input:
      set file(bfile), file(bim), file(fam) from bfile_ch
      file gte from gte_ch_gen
      val s_stat from params.GenOutThresh
      val sd_thresh from params.GenSdThresh
      val optional_pruned_variants_sex_check from params.pruned_variants_sex_check
      val ExclusionList from params.ExclusionList
      val InclusionList from params.InclusionList

    output:
      path ('outputfolder_gen') into output_ch_genotypes
      file 'outputfolder_gen/gen_data_QCd/SexCheck.txt' into sexcheck
      file 'outputfolder_gen/gen_data_QCd/*fam' into sample_qc

      """
      Rscript --vanilla $baseDir/bin/GenQcAndPosAssign.R  \
      --target_bed ${bfile} \
      --gen_exp ${gte} \
      --sample_list $baseDir/data/unrelated_reference_samples_ids.txt \
      --pops $baseDir/data/1000G_pops.txt \
      --S_threshold ${s_stat} \
      --SD_threshold ${sd_thresh} \
      --inclusion_list "${InclusionList}" \
      --exclusion_list "${ExclusionList}" \
      --output outputfolder_gen \
      --pruned_variants_sex_check "${optional_pruned_variants_sex_check}"
      """
}

process GeneExpressionQC {

    tag {GeneExpressionQC}

    input:
      file exp_mat from expfile_ch
      file gte from gte_ch_exp
      file sexcheck from sexcheck
      file geno_filter from sample_qc
      val exp_platform from params.exp_platform
      val sd from params.ExpSdThresh
      val contamination_area from params.ContaminationArea

    output:
      path ('outputfolder_exp') into output_ch_geneexpression

      script:
      if (exp_platform == 'HT12v3')
      """
      Rscript --vanilla $baseDir/bin/ProcessExpression.R  \
      --expression_matrix ${exp_mat} \
      --genotype_to_expression_linking ${gte} \
      --sex_info ${sexcheck} \
      --geno_filter ${geno_filter} \
      --platform ${exp_platform} \
      --sd ${sd} \
      --contamination_area ${contamination_area} \
      --emp_probe_mapping $baseDir/data/EmpiricalProbeMatching_IlluminaHT12v3.txt \
      --output outputfolder_exp
      """
      else if (exp_platform == 'HT12v4')
      """
      Rscript --vanilla $baseDir/bin/ProcessExpression.R  \
      --expression_matrix ${exp_mat} \
      --genotype_to_expression_linking ${gte} \
      --sex_info ${sexcheck} \
      --geno_filter ${geno_filter} \
      --platform ${exp_platform} \
      --contamination_area ${contamination_area} \
      --emp_probe_mapping $baseDir/data/EmpiricalProbeMatching_IlluminaHT12v4.txt \
      --output outputfolder_exp
      """
      else if (exp_platform == 'HuRef8')
      """
      Rscript --vanilla $baseDir/bin/ProcessExpression.R  \
      --expression_matrix ${exp_mat} \
      --genotype_to_expression_linking ${gte} \
      --sex_info ${sexcheck} \
      --geno_filter ${geno_filter} \
      --platform ${exp_platform} \
      --contamination_area ${contamination_area} \
      --emp_probe_mapping $baseDir/data/EmpiricalProbeMatching_IlluminaHuRef8.txt \
      --output outputfolder_exp
      """
      else if (exp_platform == 'RNAseq')
      """
      Rscript --vanilla $baseDir/bin/ProcessExpression.R  \
      --expression_matrix ${exp_mat} \
      --genotype_to_expression_linking ${gte} \
      --sex_info ${sexcheck} \
      --geno_filter ${geno_filter} \
      --platform ${exp_platform} \
      --contamination_area ${contamination_area} \
      --emp_probe_mapping $baseDir/data/EmpiricalProbeMatching_RNAseq.txt \
      --output outputfolder_exp
      """
      else if (exp_platform == 'AffyU219')
      """
      Rscript --vanilla $baseDir/bin/ProcessExpression.R  \
      --expression_matrix ${exp_mat} \
      --genotype_to_expression_linking ${gte} \
      --sex_info ${sexcheck} \
      --geno_filter ${geno_filter} \
      --platform ${exp_platform} \
      --contamination_area ${contamination_area} \
      --emp_probe_mapping $baseDir/data/EmpiricalProbeMatching_AffyU219.txt \
      --output outputfolder_exp
      """
      else if (exp_platform == 'AffyHumanExon')
      """
      Rscript --vanilla $baseDir/bin/ProcessExpression.R  \
      --expression_matrix ${exp_mat} \
      --genotype_to_expression_linking ${gte} \
      --sex_info ${sexcheck} \
      --geno_filter ${geno_filter} \
      --platform ${exp_platform} \
      --contamination_area ${contamination_area} \
      --emp_probe_mapping $baseDir/data/EmpiricalProbeMatching_AffyHumanExon.txt \
      --output outputfolder_exp
      """
}

process RenderReport {

    tag {RenderReport}

    publishDir "${params.outdir}", mode: 'copy', overwrite: true

    input:
      path output_gen from output_ch_genotypes
      path output_exp from output_ch_geneexpression
      path report from report_ch
      val exp_platform from params.exp_platform
      val stresh from params.GenOutThresh
      val sdtresh from params.GenSdThresh
      val expsdtresh from params.ExpSdThresh
      val contaminationarea from params.ContaminationArea

    output:
      path ('outputfolder_gen/*') into output_ch2
      path ('outputfolder_exp/*') into output_ch3
      path ('Report_DataQc*') into report_ch2
      path ('CovariatePCs.txt') into combined_covariates

      """
      # Make combined covariate file
      Rscript --vanilla $baseDir/bin/MakeCovariateFile.R

      # Make report
      cp -L ${report} notebook.Rmd

      R -e 'library(rmarkdown);rmarkdown::render("notebook.Rmd", "html_document", 
      output_file = "Report_DataQc_${params.cohort_name}.html", 
      params = list(
      dataset_name = "${params.cohort_name}", 
      platform = "${exp_platform}", 
      N = "${output_exp}/exp_data_QCd/exp_data_preprocessed.txt",
      S = ${stresh},
      SD = ${sdtresh},
      SD_exp = ${expsdtresh},
      Cont = ${contaminationarea}))'
      """
}

workflow.onComplete {
    println ( workflow.success ? "Pipeline finished!" : "Something crashed...debug!" )
}
