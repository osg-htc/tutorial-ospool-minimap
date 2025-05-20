# Long-Read Read Mapping on the OSPool

This tutorial will walk you through a long-read mapping analysis workflow using Oxford Nanopore data from the _C. elegans_ CB4856 and _C. elegans_ N2 strain Reference Genomes on the OSPool high-throughput computing ecosystem. You'll learn how to:

* Map your reads to a reference genome using Minimap2
* Breakdown massive bioinformatics workflows into many independent smaller tasks
* Submit hundreds to thousands of jobs with a few simple commands
* Use the Open Science Data Federation (OSDF) to manage file transfer during job submission

All of these steps are distributed across hundreds (or thousands!) of jobs using the HTCondor workload manager and Apptainer containers to run your software reliably and reproducibly at scale. The tutorial is built around realistic genomics use cases and emphasizes performance, reproducibility, and portability. You'll work with real data and see how high-throughput computing (HTC) can accelerate your genomics workflows.

>[!NOTE]
>If you're brand new to running jobs on the OSPool, we recommend completing the HTCondor ["Hello World"](https://portal.osg-htc.org/documentation/htc_workloads/workload_planning/htcondor_job_submission/) exercise before diving into this tutorial.

**Let’s get started!**

Jump to...
<!-- TOC start (generated with https://github.com/derlin/bitdowntoc) -->

- [Tutorial Setup](#tutorial-setup)
   * [Assumptions](#assumptions)
   * [Materials](#materials)
   * [Setting up your software environment](#setting-up-your-software-environment)
- [Mapping Sequencing Reads to Genome](#mapping-sequencing-reads-to-genome)
   * [Data Wrangling and Splitting Reads](#data-wrangling-and-splitting-reads)
      + [Splitting the FASTQ reads](#splitting-the-fastq-reads)
      + [Pre-staging our files on the Open Science Data Federation (OSDF)](#pre-staging-our-files-on-the-open-science-data-federation-osdf)
   * [Running Minimap to Map Reads to the Reference Genome](#running-minimap-to-map-reads-to-the-reference-genome)
- [Next Steps](#next-steps)
   * [Software](#software)
   * [Data](#data)
   * [GPUs](#gpus)
- [Getting Help](#getting-help)

<!-- TOC end -->

## Tutorial Setup

### Assumptions

This tutorial assumes that you:

* Have basic command-line experience (e.g., navigating directories, using bash, editing text files).
* Have a working OSPool account and can log into an Access Point (e.g., <ap40>.uw.osg-htc.org).
* Are familiar with HTCondor job submission, including writing simple .sub files and tracking job status with condor_q.
* Understand the general workflow of long-read sequencing analysis: basecalling → mapping → variant calling.
* Have access to a machine with a GPU-enabled execution environment (provided automatically via the OSPool).
* Have sufficient disk quota and file permissions in your OSPool home and OSDF directories.

>[!TIP]
>You do not need to be a genomics expert to follow this tutorial. The commands and scripts are designed to be beginner-friendly and self-contained, while still reflecting real-world research workflows.

### Materials

To obtain a copy of the files used in this tutorial, you can

* Clone the repository, with 
  
  ```
  git clone https://github.com/dmora127/tutorial-ospool-minimap.git
  ```

  or the equivalent for your device

* To copy the data files for the tutorial, we're going to use the `pelican object get <object> <destination` command. We need to `get` two files: `minimap2.sif` and `wgs_reads_cb4856.fastq `. Run the following commands from the Access Point:
  * If you are on **AP20 or AP21**
    ```
    cp /ospool/uc-shared/public/osg-training/tutorial-ospool-minimap/software/minimap2.sif ~/tutorial-ospool-minimap/software/minimap2.sif
    cp /ospool/uc-shared/public/osg-training/tutorial-ospool-minimap/data/fastq_reads/wgs_reads_cb4856.fastq ~/tutorial-ospool-minimap/data/fastq_reads/wgs_reads_cb4856.fastq
    ```
    
  * If you are on **AP40**
    ```
    cp /ospool/ap40/osg-staff/tutorial-ospool-minimap/software/minimap2.sif ~/tutorial-ospool-minimap/software/minimap2.sif
    cp /ospool/ap40/osg-staff/tutorial-ospool-minimap/data/fastq_reads/wgs_reads_cb4856.fastq ~/tutorial-ospool-minimap/data/fastq_reads/wgs_reads_cb4856.fastq
    ```
>[!TIP]
> You may be able to use:
> ```
> pelican object get pelican://osg-htc.org/ospool/uc-shared/public/osg-training/tutorial-ospool-minimap/software/minimap2.sif ~/tutorial-ospool-minimap/software/minimap2.sif
>
>pelican object get pelican://osg-htc.org/ospool/uc-shared/public/osg-training/tutorial-ospool-minimap/software/minimap2.sif ~/tutorial-ospool-minimap/data/fastq_reads/wgs_reads_cb4856.fastq
> ```
> 
>While this method is preferred, if you run into any errors the `cp` commands above are more resilient to most intermittant OSDF issues. 

### Setting up your software environment
For this tutorial, we will be using an Apptainer/Singularity container to run `minimap2`. We will be using the `continuumio/miniconda3:latest` base image from Dockerhub to `conda install` minimap2 in our container. An Apptainer/Singularity definition file has been provided to you in this repository and can be found in `./tutorial-ospool-minimap/software/minimap2.def`. 

1. Build the container by running the following commands:
    ```
    cd ~/tutorial-ospool-minimap/software/
    mkdir -p $HOME/tmp
    export TMPDIR=$HOME/tmp
    export APPTAINER_TMPDIR=$HOME/tmp
    export APPTAINER_CACHEDIR=$HOME/tmp
  
    apptainer build minimap2.sif minimap2.def
    ```

>[!TIP]
> For more information on using containers on the OSPool, visit our guide on [Apptainer/Singularity Containers](https://portal.osg-htc.org/documentation/htc_workloads/using_software/containers-singularity/)

## Mapping Sequencing Reads to Genome

### Data Wrangling and Splitting Reads

To get ready for our mapping step, we need to prepare our read files. This includes two crucial steps, splitting our reads and saving the read subset file names to a file. 

#### Splitting the FASTQ reads

1. Navigate to your `fastq_reads` directory

    ```
   cd ~/tutorial-ospool-minimap/data/fastq_reads/
   ```

2. Split the FASTQ file into subsets of `5,000` reads per subset. Since each FASTQ read consist of four lines in the FASTQ file, we can split it every `20,000` lines

    ```
   split -l 20000 wgs_reads_cb4856.fastq cb4856_fastq_chunk_
   rm wgs_reads_cb4856.fastq
   ```

2. Generate a list of the split FASTQ subset files. Save it as `list_of_FASTQs.txt` in your `~/tutorial-ospool-minimap/data/` directory. 

    ```
   ls > ~/tutorial-ospool-minimap/list_of_FASTQs.txt
   ```
   
#### Pre-staging our files on the Open Science Data Federation (OSDF)
There are some files we will be using frequently that do not change often. One example of this is the apptainer/singularity container image we will be using for run our minimap2 mappings. The Open Science Data Federation is a data lake accessible to the OSPool with built in caching. The OSDF can significantly improve throughput for jobs by caching files closer to the execution points. 

>[!WARNING]
> The OSDF caches files aggressively. Using files on the OSDF with names that are not unique from previous versions can cause your job to download an incorrect previous version of the data file. We recommend using unique version-controlled names for your files, such as `data_file_04JAN2025_version4.txt` with the data of last update and a version identifier. This ensures your files are correctly called by HTCondor from the OSDF. 

1. Move your `minimap2.sif` container to your OSDF directory. Make sure to change `<ap##>` and `<user.name>` below to the AP number (`ap20`, `ap21`, or `<ap40>`) and the OSPool username assigned to you, respectively.

    ```
   mkdir /ospool/<ap##>/data/<user.name>/tutorial-ospool-minimap/
   
   mv ~/tutorial-ospool-minimap/software/minimap2.sif /ospool/<ap##>/data/<user.name>/tutorial-ospool-minimap/minimap2.sif
   ```

### Running Minimap to Map Reads to the Reference Genome

1. Indexing our reference genome - Generating `Celegans_ref.mmi`

   1.  Create `minimap2_index.sh` using either `vim` or `nano`
        ```
       #!/bin/bash
       minimap2 -x map-ont -d Celegans_ref.mmi Celegans_ref.fa
       ```
   2. Create `minimap2_index.sub` using either `vim` or `nano`
        ```
        +SingularityImage      = "osdf:///ospool/<ap##>/data/<user.name>/tutorial-ospool-minimap/minimap2.sif"
    
        executable             = ./minimap2_index.sh
        
        transfer_input_files   = ./data/ref_genome/Celegans_ref.fa
    
        transfer_output_files  = ./Celegans_ref.mmi 
        transfer_output_remaps = "Celegans_ref.mmi = /ospool/<ap##>/data/<user.name>/tutorial-ospool-minimap/Celegans_ref.mmi"
        output                 = ./log/$(Cluster)_$(Process)_indexing_step1.out
        error                  = ./log/$(Cluster)_$(Process)_indexing_step1.err
        log                    = ./log/$(Cluster)_$(Process)_indexing_step1.log
        
        request_cpus           = 4
        request_disk           = 5 GB
        request_memory         = 5 GB 
        
        queue 1
       ```
> [!IMPORTANT]  
> Notice that we are using the `transfer_output_remaps` attribute in our submit file. By default, HTCondor will transfer outputs to the directory where we submitted our job from. Since we want to transfer the indexed reference genome file `Celegans_ref.mmi` to a specific directory, we can use the `transfer_output_remaps` attribute on our submission script. The syntax of this attribute is:
>  
>   ```transfer_output_remaps = "<file_on_execution_point>=<desired_path_to_file_on_access_point>``` 
>  
> It is also important to note that we are transferring our `Celegans_ref.mmi` to the OSDF directory `/ospool/<ap##>/data/<user.name>/tutorial-ospool-minimap/`. Since we will be reusing our indexed reference genome file for each mapping job in the next step, we benefit from the caching feature of the OSDF. Therefore, we can direct `transfer_output_remaps` to redirect the `Celegans_ref.mmi` file to our OSDF directory.

   3. Submit your `minimap2_index.sub` job to the OSPool
       ```
      condor_submit minimap2_index.sub
      ```
> [!WARNING]  
> Index will take a few minutes to complete, **do not proceed until your indexing job is completed**

2. Map our basecalled reads to the reference _C. elegans_ indexed genome - `Celegans_ref.mmi`
    
   1.  Create `minimap2_mapping.sh` using either `vim` or `nano`
       ```
       #!/bin/bash
       # Use minimap2 to map the basecalled reads to the reference genome
        ./minimap2 -ax map-ont Celegans_ref.mmi "$1" > "mapped_${1}_reads_to_genome.sam"
       ```
       
   2. Create `minimap2_mapping.sub` using either `vim` or `nano`
       ```
       +SingularityImage      = "osdf:///ospool/<ap##>/data/<user.name>/tutorial-ospool-minimap/minimap2.sif"
    
       executable             = ./minimap2_mapping.sh
       arguments              = $(read_subset_file)
       transfer_input_files   = osdf:///ospool/<ap##>/data/<user.name>/tutorial-ospool-minimap/Celegans_ref.mmi, ./data/fastq_reads/$(read_subset_file)
    
       transfer_output_files  = ./mapped_$(read_subset_file)_reads_to_genome.sam
       transfer_output_remaps = "mapped_$(read_subset_file)_reads_to_genome.sam = ./data/mappedSAM/mapped_$(read_subset_file)_reads_to_genome.sam
        
       output                 = ./log/$(Cluster)_$(Process)_mapping_$(read_subset_file)_step2.out
       error                  = ./log/$(Cluster)_$(Process)_mapping_$(read_subset_file)_step2.err
       log                    = ./log/$(Cluster)_$(Process)_mapping_$(read_subset_file)_step2.log
        
       request_cpus           = 2
       request_disk           = 4 GB
       request_memory         = 4 GB 
        
       queue read_subset_file from ./list_of_FASTQs.txt
       ```

>[!IMPORTANT]
> In this step, we **are not** transferring our outputs using the OSDF. The mapped SAM files are intermediate temporary files in our analysis and do not benefit from the aggressive caching of the OSDF. 
    
   3. Submit your cluster of minimap2 jobs to the OSPool
   
      ```
      condor_submit minimap2_mapping.sub
      ```

## Next Steps

Now that you've completed the long-read minimap tutorial on the OSPool, you're ready to adapt these workflows for your own data and research questions. Here are some suggestions for what you can do next:

🧬 Apply the Workflow to Your Own Data
* Replace the tutorial datasets with your own FASTQ files and reference genome.
* Modify the mapping submit files to fit your data size, read type, and resource needs.

🧰 Customize or Extend the Workflow
* Incorporate quality control steps (e.g., filtering or read statistics) using FastQC.
* Use other mappers or variant callers, such as ngmlr, pbsv, or cuteSV.
* Add downstream tools for annotation, comparison, or visualization (e.g., IGV, bedtools, SURVIVOR).

📦 Create Your Own Containers
* Extend the Apptainer containers used here with additional tools, reference data, or dependencies.
* For help with this, see our [Containers Guide](https://portal.osg-htc.org/documentation/htc_workloads/using_software/containers/).

🚀 Run Larger Analyses
* Submit thousands of mappings or alignment jobs across the OSPool.
* Explore data staging best practices using the OSDF for large-scale genomics workflows.
* Consider using workflow managers (e.g., [DAGman](https://portal.osg-htc.org/documentation/htc_workloads/automated_workflows/dagman-workflows/) or [Pegasus](https://portal.osg-htc.org/documentation/htc_workloads/automated_workflows/tutorial-pegasus/)) with HTCondor.

🧑‍💻 Get Help or Collaborate
* Reach out to [support@osg-htc.org](mailto:support@osg-htc.org) for one-on-one help with scaling your research.
* Attend office hours or training sessions—see the [OSPool Help Page](https://portal.osg-htc.org/documentation/support_and_training/support/getting-help-from-RCFs/) for details.

### Software

In this tutorial, we created a *starter* apptainer containers for Minimap2. This container can serve as a *jumping-off* for you if you need to install additional software for your workflows. 

Our recommendation for most users is to use "Apptainer" containers for deploying their software.
For instructions on how to build an Apptainer container, see our guide [Using Apptainer/Singularity Containers](https://portal.osg-htc.org/documentation/htc_workloads/using_software/containers-singularity/).
If you are familiar with Docker, or want to learn how to use Docker, see our guide [Using Docker Containers](https://portal.osg-htc.org/documentation/htc_workloads/using_software/containers-docker/).

This information can also be found in our guide [Using Software on the Open Science Pool](https://portal.osg-htc.org/documentation/htc_workloads/using_software/software-overview/).

### Data

The ecosystem for moving data to, from, and within the HTC system can be complex, especially if trying to work with large data (> gigabytes).
For guides on how data movement works on the HTC system, see our [Data Staging and Transfer to Jobs](https://portal.osg-htc.org/documentation/htc_workloads/managing_data/overview/) guides.

### GPUs

The OSPool has GPU nodes available for common use. If you would like to learn more about our GPU capacity, please visit our [GPU Guide on the OSPool Documentation Portal](https://portal.osg-htc.org/documentation/htc_workloads/specific_resource/gpu-jobs/).

## Getting Help

The OSPool Research Computing Facilitators are here to help researchers using the OSPool for their research. We provide a broad swath of research facilitation services, including:

* **Web guides**: [OSPool Guides](https://portal.osg-htc.org/documentation/) - instructions and how-tos for using the OSPool and OSDF.
* **Email support**: get help within 1-2 business days by emailing [support@osg-htc.org](mailto:support@osg-htc.org).
* **Virtual office hours**: live discussions with facilitators - see the [Email, Office Hours, and 1-1 Meetings](https://portal.osg-htc.org/documentation/support_and_training/support/getting-help-from-RCFs/) page for current schedule.
* **One-on-one meetings**: dedicated meetings to help new users, groups get started on the system; email [support@osg-htc.org](mailto:support@osg-htc.org) to request a meeting.

This information, and more, is provided in our [Get Help](https://portal.osg-htc.org/documentation/support_and_training/support/getting-help-from-RCFs/) page.