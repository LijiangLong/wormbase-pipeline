#!/software/bin/perl -w
#
# DESCRIPTION:
#   setting up the GenBlast pipeline
#
# Last edited by: $Author: klh $
# Last edited on: $Date: 2012-07-09 20:01:55 $

use lib $ENV{CVS_DIR};

use constant USAGE => <<HERE;
ensembl_genblast.pl options:
            -debug USER_NAME    sets email address and debug mode
            -test               use the TEST_BUILD version of the acedb database
            -store FILE_NAME    use a Storable wormbase configuration file
            -species SPECIES_NAME species name e.g. elegans
            -user NAME          database user name e.g. wormadmin 
            -password PASSWORD  database password
	    -host DBHOSTNAME    database host
	    -port DBPORT        database port
HERE

use Getopt::Long;
use Storable;

use Bio::EnsEMBL::DBSQL::DBAdaptor;

# some magic to turn off the deprecation warnings
use Bio::EnsEMBL::Utils::Exception;
verbose('OFF');

use Wormbase;
use strict;

my($debug,$test,$store,$database,$port,$user,$password,$species,$host,$dbname, $dumpace);
GetOptions(
	   'debug=s'    => \$debug,
	   'test'       => \$test,
	   'store=s'    => \$store,
	   'user=s'     => \$user,
	   'password=s' => \$password,
	   'species=s'  => \$species,
	   'host=s'     => \$host,
	   'port=s'     => \$port,
	   'dbname=s'   => \$dbname,
	   'dumpace'    => \$dumpace,
)||die(USAGE);

# WormBase setup
my $wormbase;
 if ($store) {
    $wormbase = Storable::retrieve($store)
      or croak("Can't restore wormbase from $store\n");
} else {
    $wormbase = Wormbase->new(
        -debug    => $debug,
        -test     => $test,
        -organism  => $species,
    );
}

$database = sprintf('worm_ensembl_%s',lc(ref $wormbase));

# more setup
my $log = Log_files->make_build_log($wormbase);

# check species
if ($species eq 'elegans') {
  $log->log_and_die("There is no point in projecting elegans proteins onto the elegans genome - aborting...\n");
}

$host||='farmdb1';
$port||=3306;

# MYSQL setup
my $db = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
        -host     => $host,
        -user     => $user,
        -dbname   => $dbname || $database,
        -port     => $port,
        -driver   => 'mysql', 
    );
$db->password($password);


# locations for the genome and split wormpep fasta_files
my $genblast_dir = $wormbase->autoace.'/genblast';
mkdir $genblast_dir, 0777;
my $split_wormpep_dir = "$genblast_dir/split_wormpep";
my $split_wormpep_files = "${split_wormpep_dir}/*";
my $logic_name = "GenBlast_proteins";
my $genome_dir = "$genblast_dir/genome";

if ($dumpace) { # dump the resulting analysis out as an ace file

  $log->write_to("Writing genBlastG ace files from $database\n");
  &dumpace();

} else { # run the analysis

  $log->write_to("Updating genBlastG input files for $database\n");
  
  # 1) create the split wormpep files
  
  $log->write_to("Create split wormpep files for genBlastG\n");
  &create_split_wormpep();
  
  # 2) set up the genome file and create the blast indices for it
  
  $log->write_to("Set up and index masked genome for genBlastG\n");
  &set_up_genome();
  
  # 3) clean out all old GenBlast transcripts and exons

  $log->write_to("Clean out old genBlastG results\n");
  &clean_old_results();

  # 4) clean out all input_ids for the GenBlast analysis
  
  $log->write_to("Clean out any old genBlastG jobs\n");
  &clean_input_ids();
  
  # 5) make new input_ids
  
  $log->write_to("Set up Ensembl jobs for genBlastG analysis\n");
  &make_input_ids();

}

$log->write_to("Finished.\n");
$log->mail();


#####################################################################################################

# puts new input_ids back in the input_id_analysis table 
sub make_input_ids {
  
  my $sth=$db->prepare('INSERT INTO input_id_analysis (input_id,input_id_type,analysis_id,created,result) VALUES (?,?,?,NOW(),0)');
  
  # create_input_ids for each analysis
  foreach my $analysis(&get_all_GenBlast_analysis()) {
    my @files = glob($split_wormpep_files);
    foreach my $file (@files){
      $sth->execute($file,$analysis->input_id_type_analysis->logic_name,$analysis->input_id_type_analysis->dbID);
    }
  }
}

#####################################################################################################

sub clean_old_results {


  # for each old transcript, remove its exons

  my $get_transcripts=$db->prepare('SELECT * FROM prediction_transcript WHERE analysis_id=?');
  my $del_exons=$db->prepare('DELETE FROM prediction_exon WHERE prediction_transcript_id=?');

  foreach my $analysis (&get_all_GenBlast_analysis()) {
    $get_transcripts->execute($analysis->dbID);
    my $transcripts = $get_transcripts->fetchall_arrayref()||[]; # array_ref->array_refs
    foreach my $transcript (@{$transcripts}) {
      my $prediction_transcript_id = $$transcript[0];
      $del_exons->execute($prediction_transcript_id); 
    }
  }

  # now clean out the old transcripts
  my $del_transcripts=$db->prepare('DELETE FROM prediction_transcript WHERE analysis_id=?');
  foreach my $analysis (&get_all_GenBlast_analysis()) {
    $del_transcripts->execute($analysis->dbID);
    $del_transcripts->execute($analysis->input_id_type_analysis->dbID); 
  }
      
}
  



#####################################################################################################

#  cleans the input_id_analysis table
sub clean_input_ids {
  my $del_handle=$db->prepare('DELETE FROM input_id_analysis WHERE analysis_id=?');
  my @analysis_to_clean = &get_all_GenBlast_analysis();
  foreach my $analysis (@analysis_to_clean){
    $del_handle->execute($analysis->dbID);                             # delete the parent analysis rule input_id from table input_id_analysis
    $del_handle->execute($analysis->input_id_type_analysis->dbID);     # delete the child  analysis rule input_id from table input_id_analysis
  }    
}

#####################################################################################################

# get all analysis objects for GenBlast
sub get_all_GenBlast_analysis {
  my $adb = $db->get_AnalysisAdaptor();
  return $adb->fetch_by_program_name('genblast');
}

#####################################################################################################

# take the wormpep file from elegans and split it into 100 smaller files
sub create_split_wormpep {

  # get the elegans latest proteins
  # NB we construct the path to the elegans proteins here rather than
  # use $wormbase->wormpep as that would get the proteins for the
  # current species, not elegans
  my $version = $wormbase->get_wormbase_version;
  my $wormpep = $wormbase->basedir . "/WORMPEP/wormpep" . $version . "/wormpep". $version  .".pep";

  # number of split files to create
  my $number = 100;

  mkdir $split_wormpep_dir, 0777;
  # make sure there are no files left over from last time this was run
  $wormbase->run_command("rm -rf $split_wormpep_files", $log);

  my $line = "";

  open (IN, "$wormpep") || $log->log_and_die("Can't open $wormpep\n");
 LOOP:  while (1) {
    for (my $fileno = 1; $fileno <= $number; $fileno++) {
      my $output = "$split_wormpep_dir/wormpep_$fileno";
      open (OUT, ">>$output") || $log->log_and_die("Can't open $output\n");
      print OUT $line;
      while ($line = <IN>) {
	if ($line =~ /^>/) {last;}
	print OUT $line;
      }
      close(OUT);
      if (eof(IN)) {last LOOP}
    }
  }
  close(IN);
  
}

#####################################################################################################

sub set_up_genome {

  mkdir $genome_dir, 0777;
  # make sure there are no files left over from last time this was run
  $wormbase->run_command("rm -rf $genome_dir/*", $log);
  my $target_dna_file = "$genome_dir/genome.fa";

  my $src_genome;
  if (-e $wormbase->masked_genome_seq) {
    $src_genome = $wormbase->masked_genome_seq;
  } elsif (-e $wormbase->genome_seq) {
    $src_genome = $wormbase->genome_seq;
  } else {
    $log->log_and_die("Could not find either masked or unmasked genome\n");
  }

  $wormbase->run_command("cp $src_genome $target_dna_file",$log);

  # index them for blast
  chdir $genome_dir;
# for EBI:
#  my $index_cmd = "/nfs/panda/ensemblgenomes/wormbase/software/packages/genBlastG/formatdb -i $target_dna_file -p F"
# for Sanger:
  my $index_cmd = "/software/worm/genBlastG/formatdb -i $target_dna_file -p F";
  $wormbase->run_command($index_cmd, $log);


}

#####################################################################################################
# dump the results out as an ace file

sub dumpace {

  # want to make the ace file like:

  #CDS : "JNC_CBN22119"
  #Sequence "Cbre_Contig388"
  #Species "Caenorhabditis brenneri"
  #CDS
  #Method "genBlastG"
  #Remark "Elegans homolog: Y41C4A.8, homology % ID: 80.25, homology coverage: 100"
  #Source_exons 1 186
  #Source_exons 386 507
  #Source_exons 559 961
  
  #Sequence : "Cbre_Contig388"
  #CDS_child "JNC_CBN22119" 49765 48805
  #CDS_child "JNC_CBN22128" 72744 72127
  #CDS_child "JNC_CBN22109" 4229 6130
  #CDS_child "JNC_CBN22113" 32892 33843
  #CDS_child "JNC_CBN22120" 52596 50459
  #CDS_child "JNC_CBN22123" 55861 54807
  
  my %Sequence;
  
  my $acefile = $wormbase->acefiles."/genblast.ace";
  open (ACE, "> $acefile") || $log->log_and_die("Cant open the ace file $acefile\n");

  my $get_transcripts=$db->prepare('SELECT * FROM prediction_transcript WHERE analysis_id=?');
  my $get_exons=$db->prepare('SELECT * FROM prediction_exon WHERE prediction_transcript_id=?');
  my $get_contig=$db->prepare('SELECT name FROM seq_region where seq_region_id=?');
  foreach my $analysis (&get_all_GenBlast_analysis()) {
    $get_transcripts->execute($analysis->dbID);
    #$get_transcripts->execute($analysis->input_id_type_analysis->dbID); 
    my $transcripts = $get_transcripts->fetchall_arrayref()||[]; # array_ref->array_refs
    foreach my $transcript (@{$transcripts}) {
      my $prediction_transcript_id = $$transcript[0];
      my $seq_region_id = $$transcript[1];
      my $transcript_seq_region_start = $$transcript[2];
      my $transcript_seq_region_end = $$transcript[3];
      my $transcript_seq_region_strand = $$transcript[4];
      my $prediction_transcript_display_label = $$transcript[6];
      
      # make a suitably unique name for the CDS
      my $unique_name = "GBG_${species}_${prediction_transcript_display_label}";

      $get_contig->execute($seq_region_id);
      my $contig;
      while (my ($tmp) = $get_contig->fetchrow_array) {$contig=$tmp}

      if ($transcript_seq_region_strand == 1) { # forward
	$Sequence{$contig} .= "CDS_child \"$unique_name\" $transcript_seq_region_start $transcript_seq_region_end\n";
      } else {
	$Sequence{$contig} .= "CDS_child \"$unique_name\" $transcript_seq_region_end $transcript_seq_region_start\n";
      }

      print ACE "\nCDS : \"$unique_name\"\n";
      print ACE "Sequence \"Cbre_Contig388\"\n";
      print ACE "Species \"",$wormbase->full_name(),"\"\n";
      print ACE "CDS\n";
      print ACE "Method \"genBlastG\"\n";
      print ACE "Remark \"Elegans homolog: $prediction_transcript_display_label\"\n";

      $get_exons->execute($prediction_transcript_id); 
      my $exons = $get_exons->fetchall_arrayref()||[]; # array_ref->array_refs
      foreach my $exon (@{$exons}) {
	my $seq_region_start = $$exon[4];
	my $seq_region_end = $$exon[5];
	my $seq_region_strand = $$exon[6];

	if ($seq_region_strand == 1) { # forward
	  my $start = $seq_region_start - $transcript_seq_region_start + 1;
	  my $end = $seq_region_end - $transcript_seq_region_start + 1;
	  print ACE "Source_exons $start $end\n"
	} else {
	  my $start = $transcript_seq_region_end - $seq_region_end + 1;
	  my $end = $transcript_seq_region_end - $seq_region_start + 1;
	  print ACE "Source_exons $start $end\n"	  
	}

      }
    }
  }
  

  # output the CDS_child data
  foreach my $seq (keys %Sequence) {
    print ACE "\nSequence : \"$seq\"\n";
    print ACE "$Sequence{$seq}\n\n";
  }

  close(ACE);

}

#####################################################################################################

# extensions to EnsEMBL classes
package Bio::EnsEMBL::Analysis;

sub input_id_type_analysis {
  my ($self)=@_;
  my $sth = $self->adaptor->prepare('SELECT a.analysis_id FROM input_id_type_analysis i JOIN analysis a on(i.input_id_type=a.logic_name) WHERE i.analysis_id = ?');
  $sth->execute($self->dbID);
  my $id_type;
  while (my ($tmp) = $sth->fetchrow_array){$id_type=$tmp}
  
  return $self->adaptor->fetch_by_dbID($id_type);
}

#####################################################################################################

package Bio::EnsEMBL::DBSQL::AnalysisAdaptor;

# to fetch all analysis with a certain program
sub fetch_by_program_name {
  my ($self,$program_name) = @_;
  my @returned_analysis;
  my $sth = $self->prepare('SELECT analysis_id FROM analysis WHERE program = ?');
  $sth->execute($program_name);
  my $ids = $sth->fetchall_arrayref()||[]; # array_ref->array_refs
  foreach my $analysis (@$ids){
    push @returned_analysis , $self->fetch_by_dbID($$analysis[0]);
  }
  return @returned_analysis;
}


