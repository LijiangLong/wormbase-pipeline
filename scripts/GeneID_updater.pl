#!/software/bin/perl -w
#
# GeneID_updater.pl
# 
# by Paul Davis
#
# Script to refresh various information including WBGene ID's, protein_ids, clone SV's in a chosen database from a chosen reference database.
#
# Last updated by: $Author: pad $
# Last updated on: $Date: 2008-02-28 14:53:58 $

use strict;
my $scriptdir =  $ENV{'CVS_DIR'};
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use Carp;
use Storable;
use IO::Handle;
use Socket;

######################################
# variables and command-line options #
######################################

my ($help, $debug, $geneID, $database, $sourceDB, $update, $public, $sourceDB2, $proteinID, $version, $test, $store, $wormbase, $sv, $output_dir, $verbose, $all, $operon, $info);

GetOptions (
	    'help'         => \$help, #help documentation.
	    'test'         => \$test, #test build
            'debug=s'      => \$debug, #debug option for email
	    'geneID'       => \$geneID,	#update gene id's
	    'database=s'   => \$database, #Database to check/update
	    'sourceDB=s'   => \$sourceDB, #source for gene id info
    	    'sourceDB2=s'  => \$sourceDB2, #source for protein id's
	    'output_dir=s' => \$output_dir, #Specify your own output directory
	    'proteinID'    => \$proteinID, #update protein id's option
	    'update'       => \$update,	#load ace files automatically into database being checked.
	    'public'       => \$public,	#retrieve public name info ....future
	    'version=s'    => \$version, #version number for properly directing out files in future
	    'store:s'      => \$store, #storable object
	    'sv'           => \$sv, #check sequence versions against embl
	    'verbose'      => \$verbose, # Verbose output into log messages
	    'all'          => \$all, #Do ALL (GeneID, ProteinID, Sequence version,) syncronisations.
	    'operon'       => \$operon, #Refresh operon data in camace.
	    'gene_info'    => \$info, #Refresh CGC_names and Gene_class in elegans sequence based genes.
	   );


if ($store) {
  $wormbase = retrieve($store) or croak ("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug => $debug,
			     -test => $test,
			   );
}

my %exceptions;
my $output_file;
my $output_file2;
my $output_file3;
my %models2geneID;
my $count = "0";
if (!$version) {$version = "666";}
my $next_build = ($version + 1);
my $wormpub = $wormbase->wormpub;

# tace executable path
my $tace = $wormbase->tace;

# Display help if required
&usage("Help") if ($help);

# establish log file.
my $log = Log_files->make_build_log($wormbase);

# Specify Paths and files

if (!$output_dir) {
  $output_dir = $wormpub."/camace_orig/WS${version}-WS${next_build}";
  print "Using $output_dir\n\n" if ($verbose); 
} 
my $def_dir = $wormbase->database('current')."/wquery";
my $tablemaker_query =  "${def_dir}/SCRIPT:GeneID_updater.pl.def";
my $tablemaker_query2 = "${def_dir}/SCRIPT:HXcds2protID.def";
my $canonical = $wormbase->database('camace');

# Select and check source databases.
if ($sourceDB) {
  $sourceDB = $sourceDB;
} elsif (!$sourceDB) {
  $sourceDB = $wormbase->database('geneace');
}
if ($database) {
  $database = $database;
} elsif (!$database) {
  $database = "$canonical";
}
if ($proteinID || $all) {
  if (defined ($sourceDB2)) {
    $sourceDB2 = $sourceDB2;
  }
  elsif (-e $wormpub."/BUILD/autoace/database/block1.wrm") {
    print "Using autoace for the source of protein IDs\n";
    $sourceDB2 = $wormbase->database('autoace');
  }
  else {
    $sourceDB2 = $wormbase->database('current');
  }
}

##########################
# MAIN BODY OF SCRIPT
##########################


&gene_ID if ($geneID);
&protein_ID if ($proteinID || $all);
&sv if ($sv || $all);
&operon if ($operon || $all);
&info if ($info || $all);

$log->write_to("Upload file(s) completed.......\n");

&update if ($update);
&noupdate if (!defined $update);

$log->mail();
print "Diaskeda same Poli\n";	#we had alot of fun#
exit(0);


##############################################################
#                        Subroutines                         #
##############################################################


sub gene_ID {
  &load_exceptions;                  #load know anomolies to be ignored
  $output_file = "$output_dir/updated_geneIDs_WS${next_build}\.ace";
  $log->write_to("\n==============================================================================================
geneID option selected, updating WBGeneID connections in $database
----------------------------------------------------------------------------------------------\n");
  $log->write_to("\nSOURCE Database for Gene IDs: $sourceDB.\n");
  $log->write_to("TARGET Database: $database\n");
  $log->write_to("OUTPUT FILE:$output_file.\n\n");
  $log->write_to("Opening database connection.....\n/1/ Gathering data from $sourceDB; Object Class and GeneID\n");
    
  # connect to AceDB using TableMaker, but use $wormpub/DATABASES/current_DB/wquery for Table-maker definition
  my $command = "Table-maker -p $tablemaker_query\nquit\n";
  my $gene;
  my $name;

  open (TACE, "echo '$command' | $tace $sourceDB |");
  while (<TACE>) {
    chomp;
    next if ($_ eq "");
    next if (/acedb\>/);
    #last if (/\/\//);
    
    # get rid of quote marks
    s/\"//g;

    next unless  (/^(\S+)\t(\S+)/);
    
    # split the line into various fields
    ($gene,$name) = (/^(\S+)\t(\S+)/);

    # add to hash. CDS, Pseudogene, or Transcript name is key, gene ID is value
    $models2geneID{$name} = $gene;

  }
  close TACE;

  ####################################################################
  # make database connections for looping through elegans subclasses #
  # Method   : AcePerl                                               # 
  # TargetDB : $wormpub/DATABASES/camace                             # 
  ####################################################################

  $log->write_to("/2/ Gathering data from $database; Object Class and Name\n\n");
  open (OUT, ">$output_file") or die "Can't write output to $output_file\n";

  # Retrieve model names and assign to a hash#
  my @classes = ("All_genes");

  #my $history;
  my $lookupname;
  my $geneID;
  my $query;

  my $db = Ace->connect(-path => "$database",
			-program => $tace) || do { 
			  $log->write_to("Connection failed to $database: ",Ace->error);
			  die();
			};

  $log->write_to("==============================================================================================\nERROR TABLE\n==============================================================================================\n");
  foreach my $class (@classes) {

    $query = "find $class";
    my $i = $db->fetch_many(-query => $query);
    while (my $obj = $i->next) {
      $name = $obj->name;
      my $history;
      # histories AH6.1:wp999
      next if( $exceptions{$name} )  ;
      if ($name =~ /(\S+.+)\:(\S+.+)/) {
	$lookupname = $1;
	$history    = 1;
      } else {
	$lookupname = $name;
      }
      # remove isoform letters from models with a cosmid.no name
      $lookupname =~ s/[a-z]$// unless ($lookupname =~ /\S+\.\D/);

      # lookup GeneID keyed on lookupname
      $geneID = $models2geneID{$lookupname};
		
      # Print out ace file full model name and modified class name.
      my $Tag = $obj->class;
	
      print "// $name \t$lookupname\n" if ($debug && $verbose);	# verbose debug line
      if ($Tag ne "Transposon") {
	print OUT "$Tag : \"$name\"\n";
	if (!$history) {
	  print OUT "Gene\t\"$geneID\"\n\n";
	} elsif (defined $history) {
	  print OUT "Gene_history\t\"$geneID\"\n\n" unless (!defined ($geneID));
	}
	print OUT "\n" if (!defined ($geneID));
	if (!defined ($geneID)) {
	  $log->write_to("ERROR:$name does not have a geneID please investigate.\n");
	}
	$obj->DESTROY();
      }
    }
  }
  $db->close;

  close OUT;
}

########################
#  Refresh ProteinIDs  #
########################

sub protein_ID {
  $output_file2 = "$output_dir/updated_proteinIDs_WS${next_build}.ace";
  $log->write_to("\n\n==============================================================================================\nproteinID option selected, updating WP:Protein_ID connections in $database\n----------------------------------------------------------------------------------------------\n\n");
  $log->write_to("SOURCE Database for Protein IDs: $sourceDB2.\n");
  $log->write_to("OUTPUT FILE: $output_file2\n\n"); 
  $log->write_to("Opening database connection.....\n/3/ Gathering Protein_IDs from $sourceDB2\n\n");

  # connect to AceDB using TableMaker
  my $command = "query find curated_CDS where From_laboratory = HX\nshow -t Protein_id -a -f $output_file2\nquit\n";
  system ("echo \"$command\" | $tace $sourceDB2");

  ##Hard Coded exceptions to add on the end of the ace file
  open (OUT2, ">>$output_file2") or die "Can't write output .acefile: $output_file2\n";
  print OUT2 "\nCDS	:	\"MTCE.3\"\n";
  print OUT2 "protein_id	\"MTCE\"  \"CAA38153.1\"\n";
  print OUT2 "\nCDS	:	\"MTCE.12\"\n";
  print OUT2 "protein_id	\"MTCE\"  \"CAA38154.1\"\n";
  print OUT2 "\nCDS	:	\"MTCE.16\"\n";
  print OUT2 "protein_id	\"MTCE\"  \"CAA38155.1\"\n";
  print OUT2 "\nCDS	:	\"MTCE.21\"\n";
  print OUT2 "protein_id	\"MTCE\"  \"CAA38156.1\"\n";
  print OUT2 "\nCDS	:	\"MTCE.23\"\n";
  print OUT2 "protein_id	\"MTCE\"  \"CAA38157.1\"\n";
  print OUT2 "\nCDS	:	\"MTCE.25\" \n";
  print OUT2 "protein_id	\"MTCE\"  \"CAA38158.1\"\n";
  print OUT2 "\nCDS	:	\"MTCE.26\"\n";
  print OUT2 "protein_id	\"MTCE\"  \"CAA38159.1\"\n";
  print OUT2 "\nCDS	:	\"MTCE.31\"\n";
  print OUT2 "protein_id	\"MTCE\"  \"CAA38160.1\"\n";
  print OUT2 "\nCDS	:	\"MTCE.34\"\n";
  print OUT2 "protein_id	\"MTCE\"  \"CAA38161.1\"\n";
  print OUT2 "\nCDS	:	\"MTCE.35\"\n";
  print OUT2 "protein_id	\"MTCE\"  \"CAA38162.1\"\n";
  #  $db->close;

  close OUT2;
}

########################################
#  Check Sequence versions of cosmids  #
########################################

sub sv {
  my $continue;
  my $EM_acc;
  my $EM_seqver;
  my ($EM_rel,$EM_ver,$EM_sub);
  my ($clone,$acc,$ver);


  $log->write_to("\n==============================================================================================
SV option selected, updating Clone Sequence Versions connections in $database
----------------------------------------------------------------------------------------------\n");
  $log->write_to("\nComparing SV\'s in $database against MFETCH query\n\n");
  $output_file3 = "$output_dir/sequence_version_update_WS${next_build}.ace";
  $log->write_to("OUTPUT FILE: $output_file3\n\n");
  my $command = "nosave\nTable-maker -f ".$database."/wquery/sequence_versions.def\nquit\n";

  #Genereate files and connections.
  open (OUT3,  ">$output_file3") or die "Cannot open output file $output_file3\n";
  print OUT3 "//Sequence version update ace file generated by check_sequence_versions\n";
  open (LIST, "echo '$command' | $tace $database | ") or die "cant open $database\n";

  #Process data retrieved from database.
  while (<LIST>) {
    next until (/\"\S+/);
    chomp;
    s/\"//g;
    $log->write_to("WormBase Line = $_\n")if ($debug && $verbose);
    if ((/^(\S+)\s+\S+\s+(\S+)\.(\d+)/)) {
      ($clone,$acc,$ver) = (/^(\S+)\s+\S+\s+(\S+)\.(\d+)/);
      $log->write_to("WB  Sequence version $ver\n") if ($debug && $verbose);
      #Retrieve data from mfetch embl database.
      # Example data line: ID   AL031222; SV 1; linear; genomic DNA; STD; INV; 4191 BP.
      open (GET, "/software/bin/mfetch -d embl -f id -i \"sv:$acc.\*\" |");
      while (<GET>) {
	chomp;
	$log->write_to("EMBL Line = $_\n") if ($debug && $verbose);
	
	if (/^ID\s+(\S+);\s+\S+\s+(\d+);/) {
	  print "TM line test: $_\n" if ($debug && $verbose);
	  ($EM_acc,$EM_seqver) = ($1,$2);
	  $log->write_to("EM  Sequence version $EM_seqver\n") if ($debug && $verbose);
	}
	print "Cosmids done = $count - $acc\n" if ($debug);
	if ($EM_seqver == $ver) {
	  print "-----------------------\nResult: Cool\n-----------------------\n" if ($verbose);
	} else {
	  $log->write_to("Processing $acc......\n") if !$verbose;
	  $log->write_to("ERROR: WB=$ver EMBL=$EM_seqver\n");
	  print OUT3 "\nSequence : \"$clone\"\n";
	  print OUT3 "-D Database EMBL NDB_SV\n";
	  print OUT3 "\nSequence : \"$clone\"\n";
	  print OUT3 "Database EMBL NDB_SV $acc.$EM_seqver\n";
	}
	
	if (/^DT\s+(\S+)\s+\(Rel. (\d+)\, Last updated\, Version (\d+)\)/) {
	  ($EM_rel,$EM_ver,$EM_sub) = ($2,$3,$1);
	  $log->write_to("Latest version : Rel. $EM_rel Ver. $EM_ver [$EM_sub] \n");
	}
      }
      #  $log->write_to("\n");
      $count = ($count +1);
    }
    else {
      $log->write_to("$_ is an bogus line in the data retrieved\n");
    }
  }

  close OUT3;
  close LIST;
  close GET;
}

sub info {}

sub operon {}

#######################################################
## Logging                                           ##
#######################################################

sub noupdate {
  $log->write_to("\n\n==============================================================================================\n");
  $log->write_to("ACTION\n");
  $log->write_to("==============================================================================================\n");
  $log->write_to("\n\t**You will have to manually load:\n");
  $log->write_to("\t$output_file\n") if ($geneID || $all);
  $log->write_to("\t$wormpub/camace_orig/acefiles/geneID_patch.ace\n") if ($geneID || $all);
  $log->write_to("\t$output_file2\n") if ($proteinID || $all);
  $log->write_to("\t$output_file3") if ($sv || $all);
  $log->write_to("\n\n\tinto $database\n\n");
  $log->write_to("\tCOMMANDS:\n\ttace $database -tsuser merge_split\n");
  $log->write_to("\tpparse $output_file\n") if ($geneID || $all);
  $log->write_to("\tpparse $wormpub/camace_orig/acefiles/geneID_patch.ace\n") if ($geneID || $all);
  $log->write_to("\tpparse $output_file2\n") if ($proteinID || $all);
  $log->write_to("\tpparse $output_file3\n") if ($sv || $all);
  $log->write_to("\tsave\n\tquit\n\n");
}

###################
# Upload new data #
###################
sub update {
  $log->write_to("==============================================================================================");
  $log->write_to("ACTION");
  $log->write_to("==============================================================================================");
  $log->write_to("\nLoading files........\n");
  &load_data;
}

sub load_data {
  my $command = "query find curated_CDS\nedit -D Gene\nclear\n" if ($geneID || $all);
  $command   .= "query find elegans_pseudogenes\nedit -D Gene\nclear\n" if ($geneID || $all);
  $command   .= "query find elegans_RNA_genes\nedit -D Gene\nclear\n" if ($geneID || $all);
  $command   .= "pparse $output_file\n" if ($geneID || $all);
  $command   .= "pparse $wormpub/camace_orig/acefiles/geneID_patch.ace\n" if ($geneID || $all);
  $command   .= "query find curated_CDS\nedit -D Protein_ID\nclear\n" if ($proteinID || $all);
  $command   .= "pparse $output_file2\n" if ($proteinID || $all);
  $command   .= "pparse $output_file3\n" if ($sv || $all);

  open (DB, "| $tace $database -tsuser merge_split_$next_build") || die "Couldn't open $database\n";
  print DB $command;
  close DB;

  $log->write_to("\nLoaded Files:\n$output_file\n$wormpub/camace_orig/acefiles/geneID_patch.ace\n") if ($geneID || $all);
  $log->write_to("Updated Gene data in $database\n") if ($geneID || $all);
  $log->write_to("\nLoaded File:\n$output_file2\n") if ($proteinID || $all);
  $log->write_to("Updated protein_ID data in $database\n") if ($proteinID || $all);
  $log->write_to("\nLoaded File:\n$output_file3\n") if ($sv || $all);
  $log->write_to("Updated Sequence_versions in $database\n") if ($sv || $all);
}


sub usage 
  {
    my $error = shift;
    if ($error eq "Help") {
      # Help menu
      exec ('perldoc',$0);
    }
  }

sub load_exceptions {
  %exceptions = (
		 'C54G4.7' => 1,
		 'F28A8.9' => 1,
		 'Y105E8A.30' => 1,
		 'ZK228.9' => 1,
		 'C54G4.7:yk713c3.mRNA:wp126' => 1,
		 'C54G4.7:yk728f5.mRNA:wp126' => 1,
		 'F28A8.9:wp149' => 1,
		 'Y105E8A.30a:wp128' => 1,
		 'Y105E8A.30b:wp128' => 1,
		 'ZK228.9:wp144' => 1,
		);
}

__END__

=pod

=head2 NAME - GeneID_updater.pl

=head1 USAGE

=over 4

=item GeneID_updater.pl [-options]

=back

This script removes all prediction->WBGene id connections from a chosen target database and re-synchronises these connections with a chosen reference database.  Defaults are in place for routine updating of $wormpub/DATABASES/camace with data from $wormpub/DATABASES/geneace. The script has also been modified to retrieve protein ids from the previous build and update these in a chosen target database ready for embl dumping in the next build. A second modification also allows cosmid sequence versions to be checked and the resulting .ace file to be loaded into the target batabase for resolve issues.


=head2 GeneID_updater.pl MANDATORY arguments:

=over 4

=item None,

=back

GeneID_updater.pl  OPTIONAL arguments:

=over 4

=item -h, Help.

=item -dubug, supply user ID to limit logs email distribution.

=item -geneID, specifies that gene ids are to be updated.

=item -proteinID, specifies that protein ids are to be updated.

=item -update, Load the data automatically into database.

=item -sourceDB, database from which you wish to retrieve gene_id data.

=item -sourceDB2, database from which you wish to retrieve protein data.

=item -database, database you wish to synchronise.

=public -public, populates the public name data tag in gene objects in target database.

=back

=head1 REQUIREMENTS

=item Script no longer requires /wormsrv2.

=back

=head1 AUTHOR

=over 4

=item Paul Davis (pad@sanger.ac.uk)

=back

=cut

