#!/software/bin/perl
#
# wormBLAST.pl
#
# written by Anthony Rogers
#
# Last edited by: $Author: gw3 $
# Last edited on: $Date: 2013-03-27 16:00:45 $
#
# it depends on:
#    wormpep + history
#    database_used_in_build
#    ENSEMBL/worm_lite.pl
#    ENSEMBL/lib/WormBase.pm
#    ENSEMBL/etc/ensembl_lite.yml
#    /software/worm/ensembl/ensembl-conf/<species>


use Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor;
use Bio::EnsEMBL::DBSQL::DBConnection;
use strict;

use FindBin qw($Bin);
use lib "$Bin";
use lib "$Bin/BLAST_scripts";
use lib "$Bin/ENSEMBL/lib";

use WormBase;

use Wormbase;
use Getopt::Long;
use File::Path;
use File::Copy;
use Storable;
use YAML;



my ( $species, $update_dna, $clean_blasts, $update_analysis, $update_genes);
my ( $run_brig, $copy, $WS_version,$prep_dump, $cleanup);
my ( $debug, $test, $store, $wormbase, $log, $WP_version,$yfile_name);
my $errors = 0;    # for tracking global error - needs to be initialised to 0

GetOptions(
	   'update_dna'      => \$update_dna,
	   'update_genes'    => \$update_genes,
	   'update_analysis' => \$update_analysis,
	   'prep_dump'       => \$prep_dump,
	   'version=s'       => \$WS_version,
	   'cleanup'         => \$cleanup,
	   'debug=s'         => \$debug,
	   'test'            => \$test,
	   'store:s'         => \$store,
	   'species=s'       => \$species,
	   'clean_blasts'    => \$clean_blasts,
	   'copy'            => \$copy,
	   'yfile=s'         => \$yfile_name,
	  )
  || die('cant parse the command line parameter');

my $wormpipe_dir = $ENV{'PIPELINE'};
my $scripts_dir  = $ENV{'CVS_DIR'};

# defaults
my $organism = ( $species || 'Elegans' );

if ($store) {
  $wormbase = retrieve($store)
    or croak("Can't restore wormbase from $store\n");
}
else {
  $wormbase = Wormbase->new(
			    -debug    => $debug,
			    -test     => $test,
			    -version  => $WS_version,
			    -organism => $organism,
			   );
}

# establish log file. Can't use make_build_log if the BUILD/autoace directory has been moved to DATABASES
$log = Log_files->make_log("/tmp/wormBLAST.$$",$wormbase->debug);

$WS_version ||= $wormbase->get_wormbase_version;
my $WS_old = $WS_version - 1;

my $last_build_DBs  = "$wormpipe_dir/BlastDB/databases_used_WS$WS_old";
my $database_to_use = "$wormpipe_dir/BlastDB/databases_used_WS$WS_version";

$species ||= ref $wormbase;
$species =~ tr/[A-Z]/[a-z]/;

# worm_ensembl configuration part
my $species_ = ref $wormbase;
$species =~ s/^[A-Z]/[a-z]/;

$yfile_name = $ENV{'CVS_DIR'} . "/ENSEMBL/etc/ensembl_lite.conf" if not defined $yfile_name;

# the following expands any shell shortcut chars, e.g. ~
($yfile_name) = glob("$yfile_name");
die ("Could not find conf file $yfile_name\n") if not -e $yfile_name;

my $config = ( YAML::LoadFile($yfile_name) )->{$species};

our $gff_types = ( $config->{gff_types} || "curated coding_exon" );

# mysql database parameters
#my $dba = Bio::EnsEMBL::DBSQL::DBConnection->new(
my $dba = Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor->new(
						 -user   => $config->{database}->{user},
						 -dbname => $config->{database}->{dbname},
						 -host   => $config->{database}->{host},
						 -port   => $config->{database}->{port}, 
						 -driver => 'mysql'
						)
  || die "cannot connect to db, $DBI::errstr";
$dba->dbc->password( $config->{database}->{password} );

# get a clean handle to the database to use later
my $raw_dbh = $dba->dbc->db_handle;

# build blast logic_name->analysis_id hashes.
# one for blastx and one for blastp
my %worm_dna_processIDs;
my %wormprotprocessIDs;

if (! $cleanup ) {
  %worm_dna_processIDs = %{ get_logic2analysis( $raw_dbh, '%blastx' ) };
  %wormprotprocessIDs  = %{ get_logic2analysis( $raw_dbh, '%blastp' ) };
}

####################### copy files around ######################
# for chromosome , brigpep , wormpep , remapep
#
if ($copy && !$test) { # if testing use the Build protein and DNA files, but don't overwrite them

  # copy the elegans and TierII organism blast databases
  my %core_organisms = $wormbase->species_accessors;
  $core_organisms{elegans} = $wormbase;
  foreach my $wb (values %core_organisms) {
    my $pepdir_prefix = $wb->pepdir_prefix;
    copy2acari($pepdir_prefix . 'pep');
  }
  # and copy the individual chromosome files for elegans
  copy2acari('chrom');
}

########### updating databases ###############
my ( $updated_dbs, $current_dbs ) = &update_blast_dbs() if ($copy && !$test); # if testing use the Build protein and DNA files, but don't overwrite them

my %currentDBs;#  = %{$current_dbs};se

# update mySQL database
if ($update_dna){
  &update_dna();
} elsif ($update_genes){
  &update_proteins();    # axe transcripts
}

&update_analysis() if ($update_analysis||$update_genes||$update_genes);

$log->write_to("\nFinished setting up MySQL databases\n\n");

################ cleanup dodgy blast hits -clean_blasts ##################
&clean_blasts( $raw_dbh, \%worm_dna_processIDs, \%wormprotprocessIDs ) if ($clean_blasts && !$test);  # if testing don't clean up

################## -prep_dump #####################################
if ($prep_dump && !$test) {
  
  # prepare helper files gff2cds and gff2cos
  my $autoace = $wormbase->autoace;
  my $wormpep = $wormbase->wormpep;
  if ( lc(ref $wormbase) eq 'elegans' && -e $wormbase->gff_splits . "/CHROMOSOME_X_curated.gff" ) {
    $wormbase->run_command(
			   "cat "
			   . $wormbase->gff_splits
			   . "/CHROMOSOME_*_curated.gff | $scripts_dir/BLAST_scripts/gff2cds.pl "
			   . "> $wormpipe_dir/Elegans/cds$WS_version.gff",
			   $log
			  );
    $wormbase->run_command(
			   "cat "
			   . $wormbase->gff_splits
			   . "/CHROMOSOME_*_Genomic_canonical.gff | $scripts_dir/BLAST_scripts/gff2cos.pl "
			   . "> $wormpipe_dir/Elegans/cos$WS_version.gff",
			   $log
			  );
    system("touch $wormpipe_dir/DUMP_PREP_RUN");
  } elsif(lc(ref $wormbase) ne 'elegans'){
    system("touch $wormpipe_dir/DUMP_PREP_RUN");
  } else { die( " cant find GFF files at " . $wormbase->gff_splits . "\n " ) }
  
}

##################### -cleanup ##################################
if ($cleanup && !$test) {
  $log->write_to("clearing up files generated in this build\n");
  

  my $clear_dump = "$wormpipe_dir/dumps";
  
  $log->write_to ("Removing files currently in $wormpipe_dir/last_build\n");
  eval {
    system("rm -f $wormpipe_dir/last_build/*.ace") and die;
    system("rm -f $wormpipe_dir/last_build/*.gff") and die;
    system("rm -f $wormpipe_dir/last_build/*.agp") and die;
    system("rm -f $wormpipe_dir/last_build/*.txt") and die;
    system("rm -f $wormpipe_dir/last_build/*best_blastp*") and die;
    system("rm -f $wormpipe_dir/last_build/ipi*") and die;
  };
  $@ and warn("Could not cleanly clean out  $wormpipe_dir/last_build\n");
  
  $log->write_to("moving blastp acefiles to last_build . . . \n");
  system("mv -f $clear_dump/*blastp.ace $wormpipe_dir/last_build") 
    and warn("Could not move $clear_dump/*blastp.ace");
  
  $log->write_to ("\nmoving the following to ~wormpipe/last_build . . \n");
  $log->write_to("\t$clear_dump/*.txt\n");
  system("mv -f $clear_dump/*.txt $wormpipe_dir/last_build/") and warn "cant move $clear_dump/*.txt\n";
  
  $log->write_to ("\t$clear_dump/ipi*\n");
  system("mv -f $clear_dump/ipi* $wormpipe_dir/last_build/") and warn "cant move $clear_dump/ipi*\n";
  
  $log->write_to ("\t$clear_dump/*best_blastp\n");
  system("mv -f $clear_dump/*best_blastp* $wormpipe_dir/last_build/") and warn "cant move $clear_dump/* best_blast*\n";
  
  $log->write_to ("\t$wormpipe_dir/Elegans/*\n");
  system("mv -f $wormpipe_dir/Elegans/* $wormpipe_dir/last_build/") and warn "cant move $wormpipe_dir/Elegans/*\n";
  
  $log->write_to("Removing . . . \n\t$clear_dump/*.ace\n");
  system("rm -f $clear_dump/*.ace $clear_dump/*.log") and warn "cant remove ace and log files from $clear_dump";
  
  $log->write_to ("\nRemoving the $wormpipe_dir/DUMP_PREP_RUN lock file\n");
  system("rm -f $wormpipe_dir/DUMP_PREP_RUN") && warn "cant remove $wormpipe_dir/DUMP_PREP_RUN\n";
  
  $log->write_to("\nRemoving farm output and error files from $wormpipe_dir/*\n") if $debug;
  my $scratch_dir = $wormpipe_dir;

  my %core_organisms = $wormbase->species_accessors;
  $core_organisms{elegans} = $wormbase;  
  foreach my $wb (values %core_organisms) {
    my $species_dir = 'ensembl-' . $wb->species;
    system( "rm -fr $scratch_dir/$species_dir");
    mkdir("$scratch_dir/$species_dir", 0775); # so remake it
    system("chgrp $ENV{'WORM_GROUP_NAME'} $scratch_dir/$species_dir"); # change group to nucleotide
    system("chmod g+ws $scratch_dir/$species_dir"); # group writable and inherit group
  }

  $log->write_to ("\n\nCLEAN UP COMPLETED\n\n");
}

$log->mail;

exit(0);

###############################################################################################
#
#
#                          T  H  E     S  U  B  R  O  U  T  I  N  E  S
#
#
################################################################################################

=head1 Functions

=head2 copy2acari

wrapper around BLAST_scripts/copy_files_to_acari.pl 

=cut


##########################
# copy files to the farm
sub copy2acari {
  my ($option) = shift;
  $wormbase->run_script( "BLAST_scripts/copy_files_to_acari.pl -$option", $log );
}

=head2 get_logic2analysis

get analysis_ids / logic_names filtered by a program_name

arguments : DBH , 'program'

returns: hashref of logic-names -> analysis-ids

=cut

#####################
# get logic_name -> analysis_id from the mysql database

sub get_logic2analysis {
  my ( $dbh_, $prog ) = @_;
  my $sth = $dbh_->prepare('SELECT logic_name,analysis_id FROM analysis WHERE program like ?')
    || die "cannot prepare statement, $DBI::errstr";
  $sth->execute($prog) || die "cannot execute statement, $DBI::errstr";
  my $blast = $sth->fetchall_arrayref() || die "cannot connect to db, $DBI::errstr";
  my %logic2analysis;
  map { $logic2analysis{ $_->[0] } = $_->[1] } @{$blast};
  return \%logic2analysis;
}

=head2 clean_blasts

deletes blastx / blastp below a certain evalue cutoff

arguments: DBH, hashref logic_name->analysis_id of blastps, 
hashref logic_name->analysis_id of blastx, evalue cutoff

=cut

#######################
# clean blast hits
# * in case you want to remove hsps above a certain threshold from the database

sub clean_blasts {
  my ( $dbh_, $dnaids, $pepids, $cutoff ) = @_;
  $cutoff ||= 0.001;
  while ( my ( $k, $v ) = each %$pepids ) {
    my $sth = $dbh_->do("delete FROM protein_feature WHERE evalue>=$cutoff AND analysis_id=$v")
      || die($DBI::errstr);
  }
  while ( my ( $k, $v ) = each %$dnaids ) {
    my $sth = $dbh_->do("delete FROM protein_align_feature WHERE evalue>$cutoff AND analysis_id=$v")
      || die($DBI::errstr);
  }
}


=head2 update_blast_dbs

copies and xdformats the database files

=cut

#############################
# parse the database files
#
# global variables:
#   %prevDB is like {ensembl|gadfly|...} = /flunky/filename
#   %currentDB the same

sub get_updated_database_list {
    my @updated_DBs = ();
    my @updated_dbfiles;

    # make list of database names 
    my $regexp = &get_regexp_of_database_names();

    # process old databases
    open( OLD_DB, "<$last_build_DBs" ) or die "cant find $last_build_DBs";
    my %prevDBs;

    # get database file info from databases_used_WS(xx-1) (should have been updated by script if databases changed
    #
    # get logic_name,db_file from analysis_table where program_name like '%blastp'
    my $analysis_table=$raw_dbh->prepare("SELECT logic_name,db_file FROM analysis WHERE program_file LIKE '%blastp'")
       || die "cannot prepare statement, $DBI::errstr";
    $analysis_table->execute();
    # allow the regexp to match text after the database name
    my $regexp2 = "(${regexp}.*)";
    while (my @row = $analysis_table->fetchrow_array()){
        if ($row[1] =~ /$regexp2/) {
              $prevDBs{$2} = $1;  
	}
    }

    # process current databases
    open( CURR_DB, "<$database_to_use" ) or die "cant find $database_to_use";
    while (<CURR_DB>) {
        chomp;
        if (/$regexp/) {
            $currentDBs{$1} = $_;
        }
    }
    close CURR_DB;

    # compare old and new database list
    foreach ( keys %currentDBs ) {
      print "Updating $_\n";
        if ( "$currentDBs{$_}" ne "$prevDBs{$_}" ) {
            push( @updated_DBs,     "$_" );
            push( @updated_dbfiles, $currentDBs{$_} );
        }
    }
    return @updated_dbfiles;
}
##################################
# update and copy the blastdbs
# -distribute and -update_databases

sub update_blast_dbs {
  my %_currentDBs;    # ALSO used in setup_mySQL
  my @_updated_DBs;
  
  # used by get_updated_database_list sub - when run this array is filled with databases
  # that have been updated since the prev build
  # load in databases used in previous build
  
  # make list of database names 
  my $regexp = &get_regexp_of_database_names();

  open( OLD_DB, "<$last_build_DBs" ) or die "cant find $last_build_DBs";
  while (<OLD_DB>) {
    chomp;
    if (/$regexp/) {
      $_currentDBs{$1} = $_;
    }
  }
  close OLD_DB;
  
  # check for updated Databases
  $log->write_to("Updating databases \n");
  open( DIR, "ls -l $wormpipe_dir/BlastDB/*.pep |" ) or die "readir\n";
  while (<DIR>) {
    chomp;
    if (/\/$regexp/) {
      my $whole_file = "$1" . "$'";    # match + stuff after match.
      
      $log->write_to("checking $_\n");
      if ( "$whole_file" ne "$_currentDBs{$1}" ) {
	
	# make blastable database
	$log->write_to("\tmaking blastable database for $1\n");
	$wormbase->run_command( "$ENV{'WU_BLAST_PATH'}/xdformat -p $wormpipe_dir/BlastDB/$whole_file", $log );
	$wormbase->run_command( "$ENV{'NCBI_BLAST_PATH'}/makeblastdb -dbtype prot -title $1 -in $wormpipe_dir/BlastDB/$whole_file", $log ) if ($1 eq 'wormpep');

	push( @_updated_DBs, $1 );
	
	#change hash entry ready to rewrite external_dbs
	$_currentDBs{$1} = "$whole_file";
      } else {
	$log->write_to ("\t$1 database unchanged $whole_file\n");
      }
    }
  }
  close DIR;
  
  open( NEW_DB, ">$database_to_use" ) or die "cant write updated $database_to_use";
  foreach ( keys %_currentDBs ) {
    print NEW_DB "$_currentDBs{$_}\n";
  }
  close NEW_DB;
  
  # copy the databases around
  my $blastdbdir = "$wormpipe_dir/blastdb/Worms";
  #&get_updated_database_list();
  
  # delete updated databases from $wormpipe_dir/blastdb/Worms
  foreach (@_updated_DBs) {
    $log->write_to("deleting blastdbdir/$_*\n");
    ( unlink glob "$blastdbdir/$_*" )
      or $log->write_to("WARNING: cannot delete $blastdbdir/$_*\n");
  }
  $log->write_to("deleting $blastdbdir/CHROMOSOME_*.dna\n");
  ( unlink glob "$blastdbdir/CHROMOSOME_*.dna" )
    or $log->write_to("WARNING: cannot delete $blastdbdir/CHROMOSOME_*.dna\n");
  
  # copy blastdbs
  foreach (@_updated_DBs) {
    foreach my $file_name ( glob "$wormpipe_dir/BlastDB/$currentDBs{$_}*" ) {
      $log->write_to("copying $file_name to $blastdbdir/\n");
      copy( "$file_name", "$blastdbdir/" )
	or $log->write_to("ERROR: cannot copy $file_name\n");
    }
  }
  
  # copy chromosomes
  foreach my $chr ( $wormbase->get_chromosome_names( '-prefix' => 1, ) ) {
    my $file_name = "$wormpipe_dir/BlastDB/$chr.dna";
    $log->write_to("copying $file_name to $blastdbdir/\n");
    copy( $file_name, "$blastdbdir/" )
      or $log->write_to("cannot copy $file_name\n");
  }
  return ( \@_updated_DBs, \%_currentDBs );
}

=head2 update_dna

updates the whole database

=cut

###############################
# updating the dna sequences
#
# identify seq_region and axe any genes/transcripts/exons/translations/simple_features/protein_align_features/dna on it
# make input_ids for the new one
#
# or crude one: if different snowball a new database build

sub update_dna {
  my ($dbh) = @_;
  $log->write_to ("Updating mysql databases with new clone and protein info\n");
  
  # parse it and if different recreate the whole database, as we don't want to fiddle around with coordinates for the time being
  
  $log->write_to("Updating DNA sequences in mysql database\n-=-=-=-=-=-=-=-=-=-=-\n");
  
  # worm_lite.pl magic
  my $species = $wormbase->species;
  $wormbase->run_command( "perl $ENV{'CVS_DIR'}/ENSEMBL/scripts/worm_lite.pl -yfile $yfile_name -setup -load_dna -load_genes -species $species", $log );
  
  # create analys_tables and rules
  my $db_options = sprintf(
			   "-dbhost %s -dbuser %s -dbpass %s -dbname %s -dbport %s",
			   $config->{database}->{host},   $config->{database}->{user}, $config->{database}->{password},
			   $config->{database}->{dbname}, $config->{database}->{port}
			  );
  my $pipeline_scripts = "$ENV{'WORM_PACKAGES'}/ensembl/ensembl-pipeline/scripts";
  my $conf_dir         = ($config->{confdir}||die("please set a species specific confdir in $yfile_name\n"));
  
  $wormbase->run_command( "perl $pipeline_scripts/analysis_setup.pl $db_options -read -file $conf_dir/analysis.conf", $log );
  $wormbase->run_command( "perl $pipeline_scripts/rule_setup.pl $db_options -read -file $conf_dir/rule.conf", $log );
  $wormbase->run_command( "perl $pipeline_scripts/make_input_ids $db_options -translation_id -logic SubmitTranslation", $log );
  $wormbase->run_command(
			 "perl $pipeline_scripts/make_input_ids $db_options -slice -slice_size 75000 -coord_system toplevel -logic_name SubmitSlice75k -input_id_type Slice75k",
			 $log
			);
  return 1;
}

=head2 update_proteins

updates the genes + protein features

=cut

##############################
# update genes/proteins
#
# * replaced the gene by gene updater bit with that one ... because it will at least work.
# 
sub update_proteins {

  # kill all genes/exons/etc. + associated features
  
  # kill genes;
  $raw_dbh->do('DELETE FROM gene')  or die $raw_dbh->errstr;
  $raw_dbh->do('DELETE FROM gene_stable_id')  or die $raw_dbh->errstr;
  $raw_dbh->do('DELETE FROM gene_attrib')  or die $raw_dbh->errstr;
  
  
  # kill transcripts
  $raw_dbh->do('DELETE FROM transcript') or die $raw_dbh->errstr;
  $raw_dbh->do('DELETE FROM transcript_stable_id')  or die $raw_dbh->errstr;
  $raw_dbh->do('DELETE FROM transcript_attrib')  or die $raw_dbh->errstr;
  
  # kill exons
  $raw_dbh->do('DELETE FROM exon')  or die $raw_dbh->errstr;
  $raw_dbh->do('DELETE FROM exon_stable_id')  or die $raw_dbh->errstr;
  $raw_dbh->do('DELETE FROM exon_transcript') or die $raw_dbh->errstr;
  
  # kill translations
  $raw_dbh->do('DELETE FROM translation')  or die $raw_dbh->errstr;
  $raw_dbh->do('DELETE FROM translation_stable_id')  or die $raw_dbh->errstr;
  $raw_dbh->do('DELETE FROM translation_attrib') or die $raw_dbh->errstr;
  
  
  $raw_dbh->do('DELETE FROM protein_feature')  or die $raw_dbh->errstr;
  $raw_dbh->do('DELETE FROM input_id_analysis WHERE input_id_type = "TRANSLATIONID"')  or die $raw_dbh->errstr;
  
  $raw_dbh->do('DELETE FROM meta WHERE meta_key = "genebuild.start_date"')  or die $raw_dbh->errstr;
  
  # load new ones
  
  my $db_options = sprintf('-dbhost %s -dbuser %s -dbpass %s -dbname %s -dbport %i',
			   $config->{database}->{host},   $config->{database}->{user}, $config->{database}->{password},
        $config->{database}->{dbname}, $config->{database}->{port}
			  );
  my $pipeline_scripts = "$ENV{'WORM_PACKAGES'}/ensembl/ensembl-pipeline/scripts";
  
  $wormbase->run_command("perl $ENV{'CVS_DIR'}/ENSEMBL/scripts/worm_lite.pl -yfile $yfile_name -load_genes -species $species", $log );
  $wormbase->run_command("perl $pipeline_scripts/make_input_ids $db_options -translation_id -logic SubmitTranslation", $log );
}

=head2 delete_gene_by_translation [UNUSED]

unused utility function to cascade across affected tables after deleting a gene by translation stable id (was used before for the incremental gene update)

=cut

#################
# handy utility function
#
sub delete_gene_by_translation {
  $dba->get_GeneAdaptor()->fetch_by_translation_stable_id(shift)->remove;
}

=head2 parse_genes

parses GFF files into genes, returns an list of all genes (which will break most small memory machines)

=cut


##############################
# create dummy genes from gff
#
sub parse_genes {

  my $analysis = $dba->get_AnalysisAdaptor()->fetch_by_logic_name('wormbase');
  
  my @genes;
  
  # elegans hack for build
  if ( ref($wormbase) eq 'Elegans' ) {
    foreach my $chr ( glob $config->{fasta} ) {
      my ( $path, $name ) = ( $chr =~ /(^.*)\/CHROMOSOMES\/(.*?)\.\w+/ );
      `mkdir /tmp/compara` if !-e '/tmp/compara';
      system("cat $path/GFF_SPLITS/${\$name}_gene.gff $path/GFF_SPLITS/${\$name}_curated.gff > /tmp/compara/${\$name}.gff")
	&& die 'cannot concatenate GFFs';
    }
  }
  # if it is remanei collect all needed GFFs and then split them based on their supercontig into a /tmp/ directory
  elsif (ref($wormbase) eq 'Remanei'||ref($wormbase) eq 'Pristionchus'){
    my ($path)=glob($config->{fasta})=~/(^.*)\/CHROMOSOMES\//;
    my $tmpdir="/tmp/compara/$species";
    print STDERR "mkdir -p $tmpdir\n" if $debug;
    `mkdir -p $tmpdir` if !-e "/tmp/compara/$species";
    unlink glob("$tmpdir/*.gff"); # clean old leftovers
    system("cat $path/GFF_SPLITS/gene.gff $path/GFF_SPLITS/curated.gff > $tmpdir/all.gff");
    open INF,"$tmpdir/all.gff" || die (@!);
    
    # that is quite evil due to thousands of open/close filehandle operations
    while (<INF>){
      next if /\#/;
      my @a=split;
      open OUTF,">>$tmpdir/$a[0].gff" ||die (@!);
      print OUTF $_;
      close OUTF;
    }
    close INF;
  }
  
  
  foreach my $file ( glob $config->{gff} ) {
    next if $file =~ /masked|CSHL|BLAT_BAC_END|briggsae|MtDNA/;
    $file =~ /.*\/(.*)\.gff/;
    $log->write_to ("parsing $1 from $file\n");
    my $slice = $dba->get_SliceAdaptor->fetch_by_region( 'chromosome', $1 );
    push @genes, @{ &parse_gff( $file, $slice, $analysis ) };
  }
  return \@genes;
}


=head2 parse_wormpep_history

utility function to determine what files got updated

=cut

#############
# return @new , @changed , @lost cdses based on wormpep.diff
#
sub parse_wormpep_history {
  my ($wb) = @_;
  my $wp_file = glob( $wb->wormpep . '*.diff' );
  my @new;
  my @changed;
  my @lost;
  open INF, "<$wp_file";
  while (<INF>) {
    my @a = split;
    if ( $a[0] =~ /changed/ ) {
      push @changed, $a[1];
    }
    elsif ( $a[0] =~ /new/ ) {
      push @new, $a[1];
    }
    elsif ( $a[0] =~ /lost/ ) {
      push @lost, $a[1];
    }
  }
  close INF;
  return ( \@new, \@changed, \@lost );
}

=head2 update_analysis

updates the input_ids and analysis tables based on the updated files

updates the blat input_ids

=cut

#####################################
# update blasts based on the updated_dbs
#
# * updates the analysis table with new db_files, changes the timestamp for the updated analysis to now()
# * deletes features and input_ids for updated analysis

sub update_analysis {


  my $analysis_adaptor = $dba->get_AnalysisAdaptor();

  my @analyses = @{$analysis_adaptor->fetch_all()};

  foreach my $analysis (@analyses) {

    my $program = $analysis->program;
  
    # check to see if the logic_name or program name looks like a blast database to be updated
    if (defined $program && ($program eq 'blastp' || $program eq 'blastx')) {
    
      # check to see if the blast db version is NULL or out of date compared to the latest version
      my $old_db_version = $analysis->db_version();
    
      # get the latest database version for this blast database from the database versions file
      my $db_name = $analysis->db;
      my $latest_db_version = get_db_version($db_name);
      
      # do we want to update this blast database?
      if (!$old_db_version || $old_db_version ne $latest_db_version) {
      
	my $latest_db_file_path = "$ENV{'PIPELINE'}/blastdb/Worms/$latest_db_version";

	my $analysis_id = $analysis->dbID;

	$log->write_to ("updating analysis : $analysis_id => $latest_db_file_path\n");
      
	# set the values we want to update:
	$analysis->db_version($latest_db_version);
	$analysis->db_file($latest_db_file_path);
      
	# call update on the $analysis object to write it to the database
	$analysis_adaptor->update($analysis);
	
	# now delete features and input_ids for this updated analysis
	$raw_dbh->do("DELETE FROM input_id_analysis WHERE analysis_id = ${analysis_id}")     || die "$DBI::errstr";
	$raw_dbh->do("DELETE FROM protein_feature WHERE analysis_id = ${analysis_id}")       || die "$DBI::errstr";
	$raw_dbh->do("DELETE FROM protein_align_feature WHERE analysis_id = ${analysis_id}") || die "$DBI::errstr";
      }
    }
  }


  # the Interpro stuff has its own pipeline on the EBI, so only load it on the Sanger
  if (defined $ENV{'SANGER'}) {
    # update the interpro analysis
    my $interpro_dir    = "$wormpipe_dir/blastdb/Worms/interpro_scan";
    my $interpro_date   = 1000;
    my $last_build_date = -M $last_build_DBs;
    if ( -e $interpro_dir ) {
      $interpro_date = -M $interpro_dir;
    }
    else {
      $log->write_to("ERROR: Can't find the InterPro database directory: $interpro_dir\n");
    }
    
    # see if the InterPro databases' directory has had stuff put in it since the last build
    if ( $interpro_date < $last_build_date ) {
      $log->write_to ("doing InterPro updates . . . \n");
      
      # delete entries so they get rerun
      $raw_dbh->do('DELETE FROM protein_feature WHERE analysis_id IN (select analysis_id FROM analysis WHERE module LIKE "ProteinAnnotation%")')
	|| die "$DBI::errstr";
      $raw_dbh->do('DELETE FROM input_id_analysis WHERE analysis_id IN (select analysis_id FROM analysis WHERE module LIKE "ProteinAnnotation%")')
	|| die "$DBI::errstr";
    }
  }
  
  # update BLAT stuff
  my $db_options = sprintf('-user %s -password %s -host %s -port %i -dbname %s', 
			   $config->{database}->{user}, $config->{database}->{password},$config->{database}->{host},$config->{database}->{port},$config->{database}->{dbname});
  $wormbase->run_script( "BLAST_scripts/ensembl_blat.pl $db_options -species $species", $log );    
  
  # update genBlastG stuff - not done for elegans as it projects elegans proteins onto a non-elegans genome
  if ($species ne 'elegans') {
    $wormbase->run_script( "BLAST_scripts/ensembl_genblast.pl $db_options -species $species", $log );
  }
}


##########################################
# get the version of the database file which matches the specified database_name
# searches the file 'databases_used_WSxxx' for a match to the database_name

# This only works if the Blast database 'db' name in the analysis
# table matches the start of that blast database filename.

# An error is thrown if the BLAST database file name cannot be found
# in the databases_used_WSxxx file

sub get_db_version {

  my ($db_name) = @_;

  $db_name = lc $db_name;

  my $WS = $wormbase->get_wormbase_version;

  my $version_file = "$ENV{'PIPELINE'}/BlastDB/databases_used_WS${WS}";

  my $db_version;

  open (VF, "< $version_file") || $log->log_and_die("Can't open file $version_file\n");
  while (my $line = <VF>) {
    chomp $line;
    if ($line =~ /^$db_name/) {
      $db_version = $line;
      last;
    }
  }
  close (VF);

  if (!defined $db_version) {
    $log->log_and_die ("Can't find the latest version of the BLAST database file for '$db_name' in the versions file: $version_file\n");
  }

  return $db_version;
}
##########################################
# get a list of the database names returned as a regexp

sub get_regexp_of_database_names {

  my $regexp = '(gadfly|yeast|slimswissprot|slimtrembl|ipi_human';
  my %core_organisms = $wormbase->species_accessors;
  $core_organisms{elegans} = $wormbase;
  foreach my $wb (values %core_organisms) {
    my $pepname = $wb->pepdir_prefix . 'pep';
    $regexp .= "|${pepname}"; 
  }
  $regexp .= ')';

  return $regexp;
}

__END__


#######################################
# command-line options                #
#######################################

=pod

=head2 NAME - wormBLAST.pl
            - script to manage the EnsEMBL pipeline

=head1 USAGE

wormBLAST.pl -copy -prep_dump ...

Options

=head2 -update_dna

updates the dna sequence (removes old genes+dna+features)

=head2 -update_genes

updates the genes (removes old genes + protein features)

=head2 -update_analysis

updates the blast and blat databases to the last version

=head2 -prep_dump

prepares helper files for dumping (do we need this?)

=head2 -version XYZ

overrides the WormBase Version found in the storable

=head2 -cleanup

removes dogy blast features from the database (e > 0.001)
actually they should not exist, but just in case.

=head2 -debug XYZ

redirects the log mail to XYZ

=head2 -test

creates the Storable in the TEST_BUILD directory

omits many steps that would result in changes to the Blast databases

=head2 -store XYZ

reads from XYZ storable for the WormBase object

=head2 -species XYZ

update species XYZ instead of elegans

=head2 -clean_blasts

cleans the blast logs

=head2 -copy

copy protein and chromosome files before running blast

=head2 -yfile

specify a different YAML configuration file

=cut
