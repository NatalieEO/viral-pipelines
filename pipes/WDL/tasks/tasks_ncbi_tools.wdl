version 1.0

task Fetch_SRA_to_BAM {

    input {
        String  SRA_ID
        String  docker = "quay.io/broadinstitute/ncbi-tools"
    }

    command {
        set -ex -o pipefail

        # pull reads from SRA and make a fully annotated BAM
        /opt/docker/scripts/sra_to_ubam.sh ${SRA_ID} ${SRA_ID}.bam

        # pull other metadata from SRA
        esearch -db sra -q "${SRA_ID}" | efetch -mode json -json > ${SRA_ID}.json

        cat ${SRA_ID}.json | jq -r \
            '.EXPERIMENT_PACKAGE_SET.EXPERIMENT_PACKAGE.SUBMISSION.center_name' \
            | tee OUT_CENTER
        cat ${SRA_ID}.json | jq -r \
            '.EXPERIMENT_PACKAGE_SET.EXPERIMENT_PACKAGE.EXPERIMENT.PLATFORM | keys[] as $k | "\($k)"' \
            | tee OUT_PLATFORM
        cat ${SRA_ID}.json | jq -r \
            .EXPERIMENT_PACKAGE_SET.EXPERIMENT_PACKAGE.EXPERIMENT.PLATFORM.$PLATFORM.INSTRUMENT_MODEL \
            | tee OUT_MODEL
        cat ${SRA_ID}.json | jq -r \
            '.EXPERIMENT_PACKAGE_SET.EXPERIMENT_PACKAGE.SAMPLE.IDENTIFIERS.EXTERNAL_ID|select(.namespace == "BioSample")|.content' \
            | tee OUT_BIOSAMPLE
        cat ${SRA_ID}.json | jq -r \
            .EXPERIMENT_PACKAGE_SET.EXPERIMENT_PACKAGE.EXPERIMENT.DESIGN.LIBRARY_DESCRIPTOR.LIBRARY_NAME \
            | tee OUT_LIBRARY
        cat ${SRA_ID}.json | jq -r \
            '.EXPERIMENT_PACKAGE_SET.EXPERIMENT_PACKAGE.RUN_SET.RUN.SRAFiles.SRAFile[]|select(.supertype == "Original")|.date' \
            | cut -f 1 -d ' ' \
            | tee OUT_RUNDATE
        cat ${SRA_ID}.json | jq -r \
            '.EXPERIMENT_PACKAGE_SET.EXPERIMENT_PACKAGE.SAMPLE.SAMPLE_ATTRIBUTES.SAMPLE_ATTRIBUTE[]|select(.TAG == "collection_date")|.VALUE' \
            | tee OUT_COLLECTION_DATE
        cat ${SRA_ID}.json | jq -r \
            '.EXPERIMENT_PACKAGE_SET.EXPERIMENT_PACKAGE.SAMPLE.SAMPLE_ATTRIBUTES.SAMPLE_ATTRIBUTE[]|select(.TAG == "strain")|.VALUE' \
            | tee OUT_STRAIN
        cat ${SRA_ID}.json | jq -r \
            '.EXPERIMENT_PACKAGE_SET.EXPERIMENT_PACKAGE.SAMPLE.SAMPLE_ATTRIBUTES.SAMPLE_ATTRIBUTE[]|select(.TAG == "collected_by")|.VALUE' \
            | tee OUT_COLLECTED_BY
        cat ${SRA_ID}.json | jq -r \
            '.EXPERIMENT_PACKAGE_SET.EXPERIMENT_PACKAGE.SAMPLE.SAMPLE_ATTRIBUTES.SAMPLE_ATTRIBUTE[]|select(.TAG == "geo_loc_name")|.VALUE' \
            | tee OUT_GEO_LOC
    }

    output {
        File    reads_ubam = "${SRA_ID}.bam"
        String  sequencing_center = read_string("OUT_CENTER")
        String  sequencing_platform = read_string("OUT_PLATFORM")
        String  sequencing_platform_model = read_string("OUT_MODEL")
        String  biosample_accession = read_string("OUT_BIOSAMPLE")
        String  library_id = read_string("OUT_LIBRARY")
        String  run_date = read_string("OUT_RUNDATE")
        String  sample_collection_date = read_string("OUT_COLLECTION_DATE")
        String  sample_collected_by = read_string("OUT_COLLECTED_BY")
        String  sample_strain = read_string("OUT_STRAIN")
        String  sample_geo_loc = read_string("OUT_GEO_LOC")
        File    sra_metadata = "${SRA_ID}.json"
    }

    runtime {
        cpu:     4
        memory:  "15 GB"
        disks:   "local-disk 750 LOCAL"
        dx_instance_type: "mem2_ssd1_v2_x4"
        docker:  "${docker}"
    }
}

task fetch_fastas_by_taxid_seqlen {

    input {
        String  ncbi_taxid # NCBI taxid, with out without "txid" prefix
        Int   seq_minlen # minimum sequence length to include
        Int?  seq_maxlen # max of 2147483647 (signed 32-bit int) until WDL >1.0 # maximum sequence length to include
        Int?  return_count_limit = 10000 
        String  docker = "quay.io/broadinstitute/ncbi-tools"
    }

    command {
        set -ex -o pipefail

        # pull reads from SRA and make a fully annotated BAM
        /opt/docker/scripts/fetch_fastas_by_taxid_seqlen.sh ${ncbi_taxid} ${seq_minlen} ${default="1000000000000" seq_maxlen} ./ ${return_count_limit}

        # count the number of accessions so we can emit
        wc -l < ncbi_refseq_for_txid*.seq | tr -d ' ' | tee NUM_REFERENCE_SEGMENTS
        wc -l < ncbi_representative_genome_assemblies_for_txid*.seq | tr -d ' ' | tee NUM_REPRESENTATIVE_SEQS_FETCHED_FROM_NCBI_ASSEMBLY
        wc -l < ncbi_all_genbank_seq_for_txid*_as_of_*.seq | tr -d ' ' | tee NUM_SEQS_FETCHED_FROM_GENBANK   
    }

    output {
        # fasta containing refseq sequences for the given taxid 
        # may contain multiple entries in the case of multi-chr/multi-segment species
        File ncbi_refseq_fasta  = glob("ncbi_refseq_for_txid*.fasta")[0]
        Int num_refseq_segments = read_int("NUM_REFERENCE_SEGMENTS")

        # fasta containing all sequences returned from searching NCBI Assembly for representative assemblies (comparable to searching NCBI Genome)
        File ncbi_representative_assembly_seq_fasta = glob("ncbi_representative_genome_assemblies_for_txid*.seq")[0]
        Int num_representative_assembly_seqs        = read_int("NUM_REPRESENTATIVE_SEQS_FETCHED_FROM_NCBI_ASSEMBLY")

        # fasta containing all sequences returned from GenBank, including
        # the seqs from refseq
        File ncbi_all_genbank_seqs_fasta       = glob("ncbi_all_genbank_seq_for_txid*_as_of_*.seq")[0]
        Int num_seqs_fetched_from_genbank = read_int("NUM_SEQS_FETCHED_FROM_GENBANK")

        Array[String] refseq_accessions   = read_lines(glob("refseq_for_txid*.seq")[0])
    }

    runtime {
        cpu:     4
        memory:  "15 GB"
        disks:   "local-disk 150 LOCAL"
        dx_instance_type: "mem2_ssd1_v2_x4"
        docker:  "${docker}"
    }
}
