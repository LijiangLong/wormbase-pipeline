#!/usr/local/bin/perl5.8.0 -w
# next_builder_checks.pl
#
# by Keith Bradnam
#
# A simple script to send a check list to the person who will be performing the next
# build to check the current build
#
# Last updated by: $Author: gw3 $
# Last updated on: $Date: 2013-01-29 19:51:06 $
use strict;
use warnings;
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use Ace;
use File::Compare;

my $store;                                          # to specify saved commandline arguments
my $maintainers = "All";
my ($help,$debug, $species);
my ($clones, $pfam, $seq, $wormpep, $test);


GetOptions(
	   "help"    => \$help,
	   "debug=s" => \$debug,
	   'store=s' => \$store,
	   'clones'  => \$clones,
	   'pfam'    => \$pfam,
	   'seq'     => \$seq,
	   'wormpep' => \$wormpep, 
	   'species:s'=>\$species,
	   'test'    => \$test,
);

# Display help if required
&usage("Help") if ($help);

############################
# recreate configuration   #
############################
my $wb;
if ($store) { $wb = Storable::retrieve($store) or croak("cant restore wormbase from $store\n") }
else { $wb = Wormbase->new( -debug => $debug, -test => $test, -organism => $species ) }

##########################################
# Variables Part II (depending on $wb)    #
###########################################
$debug = $wb->debug if $wb->debug;    # Debug mode, output only goes to one user
my $WS_current = $wb->get_wormbase_version;
my $wormbase = $wb;
my $tace = $wb->tace;

# Use debug mode?
if ($debug) {
    $wb->debug($debug);
}

my $log = Log_files->make_build_log($wb);

$wormpep=$pfam=$seq=$clones=1 unless($wormpep or $pfam or $seq or $clones);
if (
    $wb->species eq 'brenneri' ||
    $wb->species eq 'remanei' ||
    $wb->species eq 'japonica' ||
    $wb->species eq 'briggsae' ||
    $wb->species eq 'brugia' ||
    $wb->species eq 'pristionchus') {
  $pfam=$seq=0;
} elsif ($wb->species ne 'elegans') {
  $log->log_and_die("\tSORRY, Don't know how to check this species: $species\n");
}

$log->write_to("Checking ".$wb->full_name.": - ".$wb->orgdb."\n\n");

# check counts of tags of classes against current_DB
&classes_to_check();

my $ace;
my $aceold;
#only connect once and if required.
if($wormpep or $clones or $pfam){ 
  print "Connecting to Ace\n";
  $ace    = Ace->connect('-path' => $wormbase->orgdb);
  print "Connecting to currentdb Ace\n";
  $aceold = Ace->connect('-path' => $wormbase->database('current'));
}

# these clones are chosen because they all have protein matches to all of the protein databases blasted against
if($clones) {
  $log->write_to("##################################\nChecking clones . .\n\n");
  my @clones;
  if ($wb->species eq 'elegans') {
    @clones = qw(C25A1 F56A3 C04H5 B0432 C07A9 F30H5 C10C6 B0545 C12D8 K04F1 C02C6 AH9);
  } elsif ($wb->species eq 'brenneri') {
    @clones = qw(Cbre_Contig1 Cbre_Contig10 Cbre_Contig20 Cbre_Contig50 Cbre_Contig100 Cbre_Contig200  Cbre_Contig400 Cbre_Contig600 Cbre_Contig800);
  } elsif ($wb->species eq 'briggsae') {
    # briggae contains a mixture of data on chromosomes and supercontigs, so include both
    @clones = qw(cb25.fpc0002 cb25.fpc0011c cb25.fpc0081 cb25.fpc0143a chrI chrII);
  } elsif ($wb->species eq 'remanei') {
    @clones = qw(Crem_Contig0 Crem_Contig10 Crem_Contig15 Crem_Contig30 Crem_Contig100 Crem_Contig200 Crem_Contig300 Crem_Contig500 Crem_Contig800);
  } elsif ($wb->species eq 'japonica') {
    @clones = qw(Cjap.Contig0 Cjap.Contig10 Cjap.Contig15 Cjap.Contig30 Cjap.Contig100 Cjap.Contig200 Cjap.Contig300 Cjap.Contig500 Cjap.Contig800);
  } elsif ($wb->species eq 'brugia') {
    @clones = qw(1512607 1512612 1512619 1512644m 1512649 1512661 1512663m 1512684);
  } elsif ($wb->species eq 'pristionchus') {
    @clones = qw(Ppa_Contig0 Ppa_Contig10 Ppa_Contig15 Ppa_Contig30 Ppa_Contig100 Ppa_Contig200);
  }

  foreach my $clone (@clones) {
    $log->write_to("\n##################################\nchecking clone $clone\n");	
    my $query = "find Homol_data \"$clone:*\"";
    my @hd    = $ace->fetch(-query => $query);
    my @hdold = $aceold->fetch(-query => $query);

    # add in the BLAT Homol_data objects
    if ($wb->species eq 'brenneri' || 
	$wb->species eq 'briggsae' || 
	$wb->species eq 'brugia' || 
	$wb->species eq 'remanei') {
      $query = "find Homol_data \"*:${clone}_*\"";
      push @hd, $ace->fetch(-query => $query);
      push @hdold, $aceold->fetch(-query => $query);
    }
    if ($wb->species eq 'briggsae') {
      $query = "find Homol_data \"*:${clone}\"";
      push @hd, $ace->fetch(-query => $query);
      push @hdold, $aceold->fetch(-query => $query);
    }
    
    &check_for_missing_data(\@hd, \@hdold, 'Homol_data', 'currentdb');
    
    # check the blastx Homol_data
    my $hd;
    my $count = 0;
    foreach my $hd (@hd) {
      if ($hd->name =~ /wublastx/) {
	print $hd->name,"\n";
	$count++;
	# check for presence of an alignment of one of this type of protein to the clone.
	if (defined $hd->Pep_homol(3) ) { 
	  #$log->write_to($hd->name." OK\n");
	} else {
	  $log->error("\tERROR: Homol_data ".$hd->name." does not contain any wublastx alignments\n");
	}
      }
    }
    
    # check for 11 wublastx Homol_data objects (fly, brenenri, briggsae,
    # human, japonica, pristionchus, remanei, slimSwissProt,
    # slimTrEmbl, worm, yeast)
    my @expected = qw(fly brenneri briggsae human japonica pristionchus remanei slimSwissProt slimTrEmbl worm yeast);
    &check_for_missing_data2(\@hd, \@expected, 'Feature_data', 'what is expected');

#    if($count < 11) {
#      $log->error("\tERROR: $clone has wublastx Homol_data objects missing\n");
#    }
    
    #check Feature_data
    $query = "find Feature_data \"$clone:*\"";
    @hd    = $ace->fetch(-query => $query);
    @hdold = $aceold->fetch(-query => $query);

    &check_for_missing_data(\@hd, \@hdold, 'Feature_data', 'currentdb');

    $count = 0;
    foreach my $hd (@hd) {
      if (! defined $hd->Feature(2)) {$log->write_to("Undefined object for ".$hd."\n");next}
      print $hd->name,"\n";
      $count++;
      # check the Feature_data line
      #$log->write_to("Testing line for ".$hd->name."\n");
      if (scalar $hd->Feature(2)->row >= 3 ) {
	#$log->write_to($hd->name." OK\n");
      } else {
	$log->error("\tERROR: ".$hd->name." missing clone-length data?\n");
      }
    }
    
    if ($wb->species eq 'briggsae') {
      @expected = qw(TRF Dust); # briggsae inverted feature_data is on the clones, not the chromosomes
    } else {
      @expected = qw(TRF Dust inverted);
    }

    &check_for_missing_data2(\@hd, \@expected, 'Feature_data', 'what is expected');

  }
}

if ($seq) {
    $log->write_to("\n##################################\nChecking sequence composition . .\n\n");
    #check composition.all for n's
    my $file = $wormbase->chromosomes ."/composition.all";
    undef $/;
    open (ALL,"<$file") or $log->log_and_die("cant open $file : $!\n");
    my $in = <ALL>;
    close ALL;
    $/ = "\n";
    $in =~ /n\s+(\d+)/;
    if($1 == 0){
	$log->write_to("no n's thanksfully\n");
    }else {
	$log->error("\n\nthere are n's in the genome!\n\n");
    }

    #check composition is same as start of build
    $wormbase->run_command("ls ".$wormbase->orgdb."/CHROMOSOMES/*.dna | grep -v masked |grep -v Mt| xargs composition > /tmp/comp", $log);
    if(compare($file,"/tmp/comp") == 0) { 
	$log->write_to("composition same as start of build\n\n");
    }else {
	$log->error("composition has changed during build!\n\n");
    }
    $wormbase->run_command("rm -f /tmp/comp", $log);
}

if($pfam){
    $log->write_to("\n##################################\nChecking PFAM motifs . .\n\n");
    #check PFAM motifs have title
    my $query = "query find motif PFAM* where !Title";
    my $no_tits = $ace->count("-query"=>$query);
    if($no_tits > 20) {
	$log->error("$no_tits PFAM domains are missing a Title\n");
    }else {
	$log->write_to("Only $no_tits PFAM domains are missing a Title\n");
    }
}

if($wormpep){
    $log->write_to("\n##################################\nChecking new proteins . .\n\n");
    #check that new wormpep entries have domains and blastp
    my $new_pep_file = $wormbase->wormpep."/new_entries.".$wormbase->get_wormbase_version_name;
    open (PEP,"<$new_pep_file") or $log->log_and_die("cant open $new_pep_file : $!\n");
    my @newpeps;
    while(<PEP>) {
	if(/>(\S+)/) {
	    push(@newpeps, $1);
	}
    }
    close PEP;
    my ($Pcount, $Mcount); #pephomol motifhomol
    foreach my $pep(@newpeps){
	my $pepObj = $ace->fetch('Protein' => $wormbase->wormpep_prefix.":$pep");
	$Pcount++ if (defined $pepObj->Pep_homol);
	#print STDERR $pepObj->name," P\n" unless(defined $pepObj->Pep_homol);
	$Mcount++ if (defined $pepObj->Motif_homol);
	#print STDERR $pepObj->name," M\n" unless(defined $pepObj->Motif_homol);
    }
    if ($newpeps[0]){ # else you get a funky division by zero
     ($Pcount / scalar @newpeps < 0.5) ?
	$log->error("ERROR: more than third ($Pcount / ".scalar @newpeps.") of new proteins dont have Pep_homols\n") :
	$log->write_to("new proteins Pep_homols look ok\n");

     ($Mcount / scalar @newpeps < 0.3) ?
	$log->error("ERROR: only ($Mcount / ".scalar @newpeps.") of new proteins have Motif_homols\n") :
	$log->write_to("new proteins Motif_homols look ok\n");
    }
}

$ace->close if(defined $ace);

$log->mail;
exit;



my $log_msg= <<'LOGMSG';
1) The following 12 clones are representative of the whole genome in that
they include one Sanger and one St. Louis clone for each chromosome.  Check
each clone to ensure that it contains BLAT data (EST and mRNA), BLAST data,
waba data, gene models, UTRs etc.  Also check for presence of tandem and inverted
repeats which have gone missing in the past

i)    C25A1
ii)   F56A3
iii)  C04H5
iv)   B0432
v)    C07A9
vi)   F30H5
vii)  C10C6
viii) B0545
ix)   C12D8
x)    K04F1
xi)   C02C6
xii)  AH9

2) If the genome sequence has changed, you should inspect the clones containing
those changes to see if there are any strange errors (e.g. duplicate sets of data
which are slightly out of sync.)

3) Check ~wormpub/BUILD/autoace/CHROMOSOMES/composition.all - are there any non-ATCGN
characters

4a) Check that the latest WormPep proteins have proper protein and motif homologies
This has been a problem in some builds where all new WormPep proteins have not got any
BLAST analyses.  Pick a few random Wormpep proteins and especially check that all of
the various blastp homologies are there (human, fly, worm, yeast etc.) and try to
check at least one protein from the ~wormpub/BUILD/WORMPEP/wormpepXXX/new_entries.WSXXX file

4b) Now that we have a curated set of brigpep, should do this periodically for
C. briggase protein objects too...these now have their own set of blastp hits

5) Check PFAM Motif objects have a title tag. It is a problem if there are more than about 20.

6) Run: 
  ls ~wormpub/BUILD/autoace/CHROMOSOMES/*.dna | grep -v masked |grep -v Mt| xargs composition
Make sure this is the same as it was at the start of the build:
  cat ~wormpub/BUILD/autoace/CHROMOSOMES/composition.all
Bad Homol objects can lead to errors esp when chromosome length has been reduced

Thats all...for now!  If you are satisfied the build is ok, please inform the person
building the database. Please continue to add to this list as appropriate.

========================================================================================
LOGMSG

$log->write_to($log_msg);

$log->mail("$maintainers", "Please check the ongoing build of WS${WS_current}");

exit(0);

##############################################################
#
# Subroutines
#
##############################################################

sub usage {
    my $error = shift;

    if ( $error eq "Help" ) {

        # Normal help menu
        system( 'perldoc', $0 );
        exit(0);
    }
}

##################################################################

# check for missing data compared to currentdb, 
# (see Perl Cookbook p.126)

sub check_for_missing_data {

  my ($hd_aref, $hdold_aref, $data_name, $compared_to) = @_;    

  my %seen=();
  my @oldonly=();
  foreach my $hd (@{$hd_aref}) {$seen{$hd->name}=1} # get the name of objects in the clone in the Build
  foreach my $hdold (@{$hdold_aref}) {
    unless ($seen{$hdold->name}) {push(@oldonly, $hdold->name)} # compare them to the objects in the clone in currentDB
  }
  if (@oldonly) {
    foreach my $hd (@oldonly) {
      $log->error("\tERROR: $hd missing $data_name data compared to $compared_to\n");
    }
  }
}

##################################################################

# check for missing data compared to currentdb, 
# that compares the objects to a simple list of things that should match in a regexp

sub check_for_missing_data2 {

  my ($hd_aref, $list_aref, $data_name, $compared_to) = @_;    

  my %seen=();
  my @notseen=();
  foreach my $hd (@{$hd_aref}) {$seen{$hd->name}=1} # get the name of objects in the clone in the Build
  foreach my $expected (@{$list_aref}) {
    my $found=0;
    foreach my $seen (keys %seen) {
      if ($seen =~ /$expected/) {
	$found=1;
	last;
      }
    }
    if (!$found) {
      push @notseen, $expected;
    }
  }
  if (@notseen) {
    foreach my $hd (@notseen) {
      $log->error("\tERROR: missing $data_name '$hd' compared to $compared_to\n");
    }
  }
}

##################################################################

# these are the classes that we wish to check for differences in the numbers of tags
# the example IDs are pretty much chosen at random - if you find a better one to check, feel free to change it.

sub classes_to_check {

  my %classes = (
		 'elegans' => {
			       '2_point_data' => '190',
			       Accession_number => '1FHO_A',
			       Ace2SO => 'transposable_element_ace2so',
			       Analysis => 'Million_Mutation_Project',
			       Anatomy_function => 'WBbtf0550',
			       Anatomy_name => 'AB.prpaaapa',
			       Anatomy_term => 'WBbt:0001554',
			       Antibody => '[cgc4594]:snt-1',
			       Author => 'Accili D',
			       CDS => 'AC8.12',
			       Cell => 'ABprpaapap',
			       Cell_group => 'hypodermis',
			       Clone => 'C03B5',
			       Condition => 'cgc4489_ref',
			       Contig => 'ctg899',
			       Database => 'AceView',
			       Expression_cluster => 'WBPaper00024671:AFD_vs_AWB_downregulated',
			       Expression_pattern => 'Chronogram273',
			       Expr_profile => 'B0213.14',
			       Feature => 'WBsf000351',
			       Feature_data => 'AA193915:polyA',
			       Gene => 'WBGene00000273',
			       Genetic_code => 'Selenocysteine',
			       Gene_class => 'eva',
			       Gene_cluster => 'rDNA_cluster',
			       Gene_name => '6R55.2',
			       Gene_regulation => 'cgc6998_egl-15',
			       GO_code => 'TAS',
			       GO_term => 'GO:0000351',
			       Grid => 'Y87-96',
			       Homology_group => 'COG0471',
			       Homol_data => 'AC3:Expr',
			       Homol_data => 'AC3:Mass-spec',
			       Homol_data => 'AC3:RepeatMasker',
			       Homol_data => 'AC3:RNAi',
			       Homol_data => 'AC3:SAGE',
			       Homol_data => 'AC3:TEC_RED',
			       Homol_data => 'AC3:wublastx_brenneri',
			       Homol_data => 'AC3:wublastx_briggsae',
			       Homol_data => 'AC3:wublastx_fly',
			       Homol_data => 'AC3:wublastx_human',
			       Homol_data => 'AC3:wublastx_japonica',
			       Homol_data => 'AC3:wublastx_pristionchus',
			       Homol_data => 'AC3:wublastx_remanei',
			       Homol_data => 'AC3:wublastx_slimSwissProt',
			       Homol_data => 'AC3:wublastx_slimTrEmbl',
			       Homol_data => 'AC3:wublastx_worm',
			       Homol_data => 'AC3:wublastx_yeast',
			       Interaction => 'WBInteraction000000162',
			       Laboratory => 'RW',
			       Library => 'Vancouver_fosmid',
			       Life_stage => 'WBls:0000072',
			       Locus => 'syP8',
			       Map => 'X',
			       Mass_spec_experiment => 'Zhu_1',
			       Mass_spec_peptide => 'MSP:AAAEEYPVDIVDLSDDFK',
			       Method => 'miRNA_primary_transcript',
			       Microarray => 'WashU_GSC_C.elegans_Genome_Array',
			       Microarray_experiment => 'WBPaper00013462:14_days_N2_5',
			       Microarray_results => '172031_x_at',
			       Molecule => 'WBMol:00000194',
			       Motif => 'BlnI',
			       Movie => '012.C12.i2.z7.mov',
			       Multi_pt_data => '913',
			       Oligo => 'cenix:11-b10_T7',
			       Oligo_set => '172031_x_at',
			       Operon => 'CEOP2352',
			       Paper => 'WBPaper00000277',
			       PCR_product => 'cenix:12-h8',
			       Person => 'WBPerson10000',
			       Person_name => 'A Gottschalk',
			       Phenotype => 'WBPhenotype:0000195',
			       Picture => '295_BC10719.png',
			       Position_Matrix => 'WBPmat00000273',
			       Pos_neg_data => '1417',
			       Protein => 'ENSEMBL:ENSMUSP00000042619',
			       Protein => 'WP:CE10000',
			       Pseudogene => 'C44C10.2',
			       Rearrangement => 'meDf5',
			       RNAi => 'WBRNAi00000273',
			       SAGE_tag => 'SAGE:aaaaaaaaatccacgtt',
			       Sequence => 'yk786f06.5',
			       Sequence_collection => 'Genome:C_elegans-WBcel235',
			       SK_map => 'AH10.1:Sep2001',
			       SO_term => 'SO:0000458',
			       Species => 'Achromobacter cycloclastes',
			       Strain => 'BC2420',
			       Structure_data => 'WBStructure000191',
			       Transcript => 'B0205.9',
			       Transcription_factor => 'WBTranscriptionFactor000119',
			       Transgene => 'eIs2137',
			       Transposon => 'WBTransposon00000195',
			       Transposon_family => 'TURMOIL2',
			       Tree => 'Z4.aaa post-emb lineage male vers 2',
			       TreeNode => 'ABarppppp',
			       Variation => 'WBVar00000273',
			      },
		 'briggsae' => {
			       Ace2SO => 'transposable_element_ace2so',
			       Analysis => 'RNASeq.briggsae.L4_larva',
			       CDS => 'CBG00033',
			       Clone => 'CBG29121',
			       Condition => 'RNASeq.briggsae.L4_larva',
			       Feature => 'WBsf028129',
			       Feature_data => 'AF520619:TSL',
			       Gene => 'WBGene00086998', # misses Ortholog Ortholog_other Other_name
			       Gene_name => 'Cbr-glb-26',
			       Homol_data => 'cb25.fpc2220b:wublastx_slimSwissProt',
			       Method => 'cDNA_for_RNAi',
			       Protein => 'ENSEMBL:ENSMUSP00000042619',
			       #Pseudogene => '',
			       Transcript => 'CBG00122',
			       Variation => 'WBVar00000752',

			       },
		 'brenneri' => {
			       Ace2SO => 'transposable_element_ace2so',
			       Analysis => 'RNASeq.brenneri.L4_larva.Replicate2',
			       CDS => 'CBN00033',
			       Clone => 'CBN32995',
			       Condition => 'RNASeq.brenneri.L4_larva.Replicate2',
			       Feature_data => 'Cbre_Contig0:RNASeq_forward_reads',
			       Gene => 'WBGene00158496', # misses Ortholog Ortholog_other Other_name
			       Gene_name => 'Cbn-acly-2',
			       Homol_data => 'BLAT_EST:Cbre_Contig0_18',
			       Method => 'cDNA_for_RNAi',
			       Pseudogene => 'CBN09775',
			       Transcript => 'CBN00079',
			       },
		 'remanei' => {
			       Ace2SO => 'transposable_element_ace2so',
			       Analysis => 'RNASeq.remanei.L2_larva.Replicate1',
			       CDS => 'CRE00076',
			       Clone => 'CRE32638',
			       Condition => 'RNASeq.remanei.L4_larva.Replicate2',
			       Feature_data => 'AY589598:TSL',
			       Gene => 'WBGene00051012', # misses Ortholog Ortholog_other Other_name
			       Gene_name => 'Cre-acd-1',
			      },
		 'japonica' => {
			       Ace2SO => 'transposable_element_ace2so',
			       Analysis => 'RNASeq_Hillier.japonica.L4_larva_Replicate',
			       CDS => 'CJA00088',
			       Clone => 'CJA46583',
			       Condition => 'RNASeq_Hillier.japonica.L4_larva_Replicate',
			       Feature_data => 'CA758779:low',
			       Gene => 'WBGene00119208', # misses Ortholog Ortholog_other Other_name
			       Gene_name => 'Cjp-acd-5',
			       Transcript => 'CJA00088',
			       },
		 'pristionchus' => {
			       CDS => 'PPA00099',
			       Feature_data => 'AA191935:polyA_site',
			       Gene => 'WBGene00089610', # misses Ortholog Ortholog_other Other_name
			       Gene_name => 'Ppa-abcf-1',
				   },
		 'brugia' => {
			       Ace2SO => 'coding_transcript_ace2so',
			       CDS => 'Bm4144c',
			       Condition => 'RNASeq.brugia.ERP000948.adult_female',
			       Feature => 'WBsf899556',
			       Feature_data => '1512607:Dust',
			       Gene => 'WBGene00220262', # misses Ortholog Ortholog_other Other_name
			       Gene_name => 'Bm-aagr-4',
			       Homol_data => '1512607:wublastx_brenneri',
			       Method => 'BLAT_EST_BEST',
			       Protein => 'BM:BM00001',
			       #Pseudogene => '',
			       Transcript => 'Bm1',
			     },

		);

  my $species = $wb->species;
  
  foreach my $class (keys %{$classes{$species}}) {
    my $id = $classes{$species}{$class};
    print "Checking tags in $class : \"$id\"\n";
    &check_for_missing_tags($class, $id);
  }


}


##################################################################

# check for differences in the numbers of all tags in an object
# the tace command show -a gives a output that is easy to parse, like:

#Sequence : "AC3"
#DNA	 "AC3" 38951
#Gene_child	 "WBGene00195634" 30835 30983
#Gene_child	 "WBGene00199275" 25396 25250
#CDS_child	 "AC3.1:wp98" 5575 7013
#CDS_child	 "AC3.3" 18739 17380
#Transcript	 "AC3.14" 30835 30983
#Transcript	 "AC3.15" 25396 25250
#Transcript	 "AC3.16" 17679 17828
#Pseudogene	 "AC3.9" 11805 13838
#Pseudogene	 "AC3.13" 17199 16871
#Pseudogene	 "AC3.12:wp227" 16245 15940
#Genomic_non_canonical	 "WRM0623cH01" 1614 36865
#PCR_product	 "cenix:116-g2" 9726 10433
#PCR_product	 "cenix:137-a1" 27145 28341
#PCR_product	 "cenix:18-a1" 30698 31254
#Allele	 "WBVar00001390" 615 615
#Allele	 "WBVar00001395" 3025 3025
#Allele	 "WBVar00001400" 4819 4819
#Oligo_set	 "Aff_AC3.1" 6262 7013
#Oligo_set	 "Aff_AC3.2" 12439 13179
#Oligo_set	 "Aff_AC3.3" 17979 17380
#Feature_object	 "WBsf016834" 25468 25469
#Feature_object	 "WBsf017331" 30436 30441
#Feature_object	 "WBsf017332" 30455 30456
#Homol_data	 "AC3:RNAi" 1 38951
#Homol_data	 "AC3:SAGE" 1 38951
#Source	 "SUPERLINK_CB_V"
#Overlap_right	 "F15H10" 38848
#Overlap_left	 "K07C5"
#Clone_left_end	 "AC3" 1
#Clone_left_end	 "F15H10" 24902
#Clone_right_end	 "K07C5" 5515
#Clone_right_end	 "AC3" 38951
#Database	 "EMBL" "NDB_AC" "Z71177"
#Database	 "EMBL" "NDB_SV" "Z71177.3"
#DB_remark	 "[121025] Sequence correction: SNP 0 bases  @ 34693"
#Keyword	 "HTG"
#EMBL_dump_info	 EMBL_dump_method "worm_EMBL-dump"
#From_author	 "McMurray AA"
#From_laboratory	 "HX"
#Date_directory	 "030414"
#Species	 "Caenorhabditis elegans"
#Strain	 "N2"
#Clone	 "AC3"
#Remark	 "[041026 pad] Genome sequencing error was corrected, removed a single G from position 29071 within the clone." Paper_evidence "WBPaper00024276"
#Remark	 "[041026 pad] Genome sequencing error was corrected, removed a single G from position 29071 within the clone." Accession_evidence "NDB" "BJ109865"
#Genomic_canonical	
#MD5	 "e4ead5658016c4defc883e270a20638d"
#Finished	 1995-12-21


sub check_for_missing_tags {

  my ($class, $id) = @_;

  my $db = $wb->orgdb;
  my $current = $wb->database('current');


  my @db_slurp = get_tace($class, $id, $db);
  my @current_slurp = get_tace($class, $id, $current);

  map {$_ =~ s/^(\S+).*/$1/} @db_slurp; # replace each element of the array with the first word of each element
  map {$_ =~ s/^(\S+).*/$1/} @current_slurp; # replace each element of the array with the first word of each element
  map {$_ =~ s/\n//} @db_slurp; # remove newline
  map {$_ =~ s/\n//} @current_slurp; # remove newline

  # The non-elegans species have a few tags missing from the Gene class
  # Ortholog Ortholog_other Other_name
  if ($wb->species ne 'elegans' && $class eq 'Gene') {
    @db_slurp = grep {!/(Ortholog|Ortholog_other|Other_name)/} @db_slurp; # remove Ortholog Ortholog_other Other_name
    @current_slurp  = grep {!/(Ortholog|Ortholog_other|Other_name)/} @current_slurp; # remove Ortholog Ortholog_other Other_name
  }

  my %db_count;
  my %current_count;
  
  foreach my $tag (@db_slurp) {$db_count{$tag}++} # count the unique tags
  foreach my $tag (@current_slurp) {$current_count{$tag}++} # count the unique tags

  foreach my $tag (keys %current_count) {
    my $cc = $current_count{$tag};
    if (! exists $db_count{$tag}) {
      $log->error("ERROR: $class : \"$id\" is missing all '$tag' tags. There were $cc in current_DB.\n")
    } else {
      if ($db_count{$tag} < $current_count{$tag} * 0.9) { # if lost more than 10% then throw an error
	my $diff = $current_count{$tag} - $db_count{$tag};
	$log->error("ERROR: $class : \"$id\" has lost $diff '$tag' tags. There were $cc in current_DB.\n")
      }
    }
  }

}

##################################################################
# open tace connection to get the object and slurp up the contents

sub get_tace {
  my ($class, $id, $db) = @_;

  my $cmd = "find $class $id\nshow -a\nquit\n";
  open (TACE, "echo '$cmd' | $tace $db |");
  my @slurp = <TACE>;
  close TACE;

  return @slurp;
}


##################################################################


__END__

=pod

=head1 NAME - next_builder_checks.pl

=head1 USAGE

=over 4

=item next_builder_checks.pl --user <user>

=back

This script simply sends a list of check items to the next person doing the build.
They should 'sign off' on each build and hand back to the main person when they
are happy all is ok.

=item MANDATORY arguments: -user <valid unix username>

Needed to send email

=back

=over 4

=item OPTIONAL arguments: -help, -debug <user>


 
=head1 AUTHOR - Keith Bradnam

Email krb@sanger.ac.uk


=cut
