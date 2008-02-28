#!/software/bin/perl -w
#
# merge_split_camaces.pl
# 
# A script to make multiple copies of camace for curation, and merge them back again
#
# Last edited by: $Author: pad $
# Last edited on: $Date: 2008-02-28 11:09:54 $
#
# Persisting errors.
#running csh -c "reformat_acediff file 1 file2"
#Use of uninitialized value in concatenation (.) or string at /reformat_acediff line 121.
#====================

use strict;
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use Log_files;
#use Storable;

##############################
# command-line options       #
##############################

my $all;                   # All
my $pad;                   # Use Paul's split
my $gw3;                   # Use Gary's split
my $ar2;                   # Use Anthony's split
my $merge;                 # Merging databases
my $split;                 # Splitting databases
my $update;                # Update current database
my $debug;                 # Debug option
my $help;                  # Help menu
my $version;               # Removes final wormsrv2 dependancy.
my $store;                 # Storable not needed as this is not a build script!
my $test;
my $wormbase;
my $extra;                 # remove the GeneIDupdater call as this is run outside this script.
my $email;                 # Option for child scripts that can tace a user email option.
my $nodump;                # don't dump from split camaces.
my $blastx;                # update the blastx data this option is interactive as passwords are required.

  GetOptions (
	      "all"        => \$all,
	      "pad"        => \$pad,
	      "gw3"        => \$gw3,
	      "ar2"        => \$ar2,
	      "merge"      => \$merge,
	      "split"      => \$split,
	      "update"     => \$update,
	      "help"       => \$help,
	      "debug:s"    => \$debug,
	      "version:s"  => \$version,
	      "store"      => \$store,
	      "test"       => \$test,
	      "extra"      => \$extra,
	      "email:s"    => \$email,
	      "nodump"     => \$nodump,
	      "blastx"     => \$blastx,
	     );



# Help pod if needed
&usage("Help") if ($help);

if ($store) {
  $wormbase = retrieve($store) or croak ("Can't restore wormbase from $store\n");
} 
else {
  $wormbase = Wormbase->new( -debug => $debug,
			     -test => $test,
			   );
}

my $log = Log_files->make_build_log($wormbase);

my $tace = $wormbase->tace;
my $WS_version = $version;

my $next_build = $WS_version + 1;
print "WS_version : $WS_version\tWS_next : $next_build\n" if ($debug);

my @databases; #array to store what splits are to be merged.
#my $path_new = ();
#my $path_ref = ();
my @classes = ('Transposon', 'Transcript', 'CDS', 'Sequence', 'Feature', 'Feature_data', 'Pseudogene', 'dna');
my $split_db;

# load @databases array with user database names.
push(@databases,"orig");
push(@databases,"pad") if ($pad || $all);
push(@databases,"gw3") if ($gw3 || $all);
push(@databases,"ar2") if ($ar2 || $all);

# directory paths
my $wormpub = $wormbase->wormpub;
our $canonical = $wormbase->database('camace');
our $directory   = $wormpub."/camace_orig/WS${WS_version}-WS${next_build}";
print "OUTPUT_DIR: ".$wormpub."/camace_orig/WS${WS_version}-WS${next_build}\n\n";

#################################################
## (1) Merge split databases #1 - do the diffs ##
#################################################

if ($merge) {
  
  if (!-e $directory) {
    print "New directory : '$directory'\n\n" if ($debug);
    mkdir ($directory) or die "Failed to create ${directory}\n";
  }
  else {
print "Using existing directory : '$directory'\n\n" if ($debug);
}

  print "You are merging Data from " . (join '-',@databases) ."\n\n";

  # dumps the Pseudogene, Transcript, Feature and Sequence classes from the database
  &dump_camace unless ($nodump);

  ##   All of the raw data is now dumped to files    ##

  #remove 1st element of array as there aren't going to be any camace_orig updates
  shift (@databases);
  # run acediff on the files tidy up and reformat the diff files ready to be loaded
  my $script_path = glob("~pad/wormbase/scripts");
  foreach my $database (@databases) {
    foreach my $class (@classes) {
      my $path_new = $directory . "/${class}_${database}.ace";
      my $path_ref = $directory . "/${class}_orig.ace";
      $wormbase->run_command("csh -c \"/software/worm/bin/acedb/acediff $path_ref $path_new >! $directory/${class}_diff_${database}.ace\"", $log) && die "Failed to run acediff for ${path_new}\n";
      $wormbase->run_script("reformat_acediff -file $directory/${class}_diff_${database}.ace -fileout $directory/update_${class}_${database}.ace", $log) && die "Failed to run reformat ace file for $directory/${class}_diff_${database}.ace\n";
    }
  }
  print "Phase 1 finished and all files can be found in $directory\n";
}

#################################################################
## (2) synchronises Canonical Database with the split versions ##
#################################################################

if ($update) {
  shift (@databases);
  &update_camace;
  print "Phase 2 finished $canonical is now updated\n";
}

############################################################################
## (3) TransferDB calls to move Canonical Database to the split databases ##
############################################################################

if ($split) {
  print "Removing old split databases and Copying $canonical database to the split camaces\n";
#  if ($debug){shift (@databases)};
  &split_databases;
  
# Remove data we don't want in the build.
    &remove_data("camace",);

print "Phase 3 finished. All ~wormpub split camaces can now be used\n\nCheck all TransferDB log files for \"ended SUCCESSFULLY\"\n";
}

####################################################
## Update and load blastx results to the database ##
####################################################
if ($blastx) {

  print "Update blastx results in $canonical\n\n\n        THIS IS AN INTERACTIVE SESSION SO STICK AROUND!!!\n\n\n\n";
  $wormbase->run_script("misc/split_blastx_by_centre.pl -version $WS_version", $log) && die "Failed to generate newblastx data for camace using split_blastx_by_centre.pl\n";
  $ENV{'ACEDB'} = $canonical;
  &loadace("$directory/CAM_blastx.ace", 'merge_split_blastx') or die "Failed to load new blastx_data\n";
  print "Updated blastx data in $canonical\n\n";
}

print "Diaskeda same Poli\n"; #we had alot of fun#
$log->mail();
exit(0);

##################################################################################################################################################
                                                                #################
                                                                #  Subroutines  #
                                                                #################
##################################################################################################################################################



##########################################################
#3) remove secret data.                                  #
##########################################################
sub remove_data {
  my $sub_database = shift;
  my $database_path = $wormpub."/DATABASES/${sub_database}";
  $ENV{'ACEDB'} = $database_path;
  my $command;
  #remove homol tiling data.
  $command  = "query find Homol_data *tiling*\n";
  $command .= "kill\n";
  $command .= "y\n";
  #remove sequence tiling data.
  $command .= "query find Sequence *tiling*\n";
  $command .= "kill\n";
  $command .= "y\n";
  #remove anomoly motif data.
  $command .= "query find Motif *curation_anomaly\n";
  $command .= "kill\n";
  $command .= "y\n";
  #remove anomoly Homol_data.
  $command .= "query find Homol_data *curation_anomaly\n";
  $command .= "kill\n";
  $command .= "y\n";
  #Save the database.
  $command .= "save\n";
  $command .= "quit\n";
  print "Removing tiling array data.\n";
  open (TACE,"| $tace") or die "Failed to open database connection\n";
  print TACE $command;
  close TACE;
}

##########################################################
#(1) remove secret data and dump files from camace splits#
##########################################################
sub dump_camace {
  #dumps out subset of classes from camace splits and processes the files to be loaded back to Canonical Database
  #array of classes to be dumped
  my $camace_path;
  my $path;

  foreach my $database (@databases) {

    $camace_path = $wormpub."/camace_${database}";
    $ENV{'ACEDB'} = $camace_path;
    
    foreach my $class (@classes) {
      print "dumping $class class from camace_${database}\n";
      $path = "$directory/" . "${class}_${database}.ace";
      &dumpace("$class",$path);
      print "dumped $class class from camace_${database}\n\n";
    }
  }
}

####################
#(1a)data retrieval#
####################
sub dumpace {
  my $class    = shift;
  my $filepath = shift;
  
  my $command = "nosave\nquery find $class\nshow -a -f $filepath\nquit\n";
  
  # dump out from ACEDB
  print "\nFilename: $filepath\n";
  open (TACE,"| $tace") or die "Failed to open database connection\n";
  print TACE $command;
  close TACE;
}

################
#(2a)data upload#
################
sub loadace {
  my $filepath = shift;
  my $tsuser   = shift;

  if ($tsuser =~ /\S+\s/) {print "ERROR: tsuser contains white space!!\n"; die "Failed to open database connection because of tsuser :(\n"}
  my $command = "pparse $filepath\nsave\nquit\n";

  # dump out from ACEDB
  print "\nFilename: $filepath\n";
  open (TACE,"| $tace -tsuser $tsuser") or die "Failed to open database connection\n";
  print TACE $command;
  close TACE;
}

#######################################
#(2b)upload data to Canonical Database#
#######################################
sub update_camace {
  # upload processed diff files into Canonical Database.
  print "Upload diff files to $canonical";
  $ENV{'ACEDB'} = $canonical;
  
  ##################################################################
  ##  Upload the split camace update files you have just created  ##
  ##################################################################
  foreach my $database (@databases) {
    foreach my $class (@classes) {
      &loadace("$directory/update_${class}_${database}.ace","${database}");
    }
  }
  #####################################
  ## upload BLAT results to database ##
  #####################################
  print "\n\nUpdate BLAT results in $canonical\n";
   $wormbase->run_script("load_blat2db.pl -all -dbdir $canonical", $log) && die "Failed to run load_blat2db.pl\n";
  
  ############################################################
  ## Remove old and update new anomaly and orientation data ##
  ############################################################
  &remove_data("camace",);
  $ENV{'ACEDB'} = $canonical;
  &loadace("$wormpub./CURATION_DATA/anomalies.ace", 'curation_anomaly_data') or die "Failed to load new curation data\n";
  print "Updated anomaly data in $canonical\n\n";

  &loadace($wormpub."/CURATION_DATA/tiling_array.ace", 'tiling array data') or die "Failed to load tiling array data\n";
  print "Updated tiling array data in $canonical\n\n";

  print "Looking for /nfs/disk100/wormpub/CURATION_DATA/assign_orientation.WS${version}.ace.......................\n";
  if (-e "/nfs/disk100/wormpub/CURATION_DATA/assign_orientation.WS${version}a.ace") {
    print "File present.....Updating Transcript orientation from WS${version} for the next build.\n";
    &loadace("/nfs/disk100/wormpub/CURATION_DATA/assign_orientation.WS${version}a.ace", 'transcript_orientation_data') or die "Failed to load new orientation data\n";
    print "Updated Transcript orientations\n\n";
  }
  else {print "Orientation data was not present at this point in the build so will need to be loaded later on, but before the next build!!!!!\n\n";}

  ##################################################################################
  ## Update Protein ID's and check embl sequence_versions                         ##
  ##################################################################################
  print "\n\nRunning Gene_ID_update.pl to refresh Protein_ID\'s\n\n";
  $wormbase->run_script("GeneID_updater.pl -proteinID -sv -version $WS_version -update", $log) && die "Failed to run Gene_ID_updater.pl\n";
  print "Updated Protein_ID\'s and clone Sequence_versions\n";

  ######################################################
  ## Check if camace is in sync with the name server. ##
  ######################################################

  print "\n\nRunning camace_nameDB_comm.pl.\n\n";
  $wormbase->run_script("NAMEDB/camace_nameDB_comm.pl", $log) && die "Failed to run camace_nameDB_comm.pl\n";
  print "camace_nameDB_comm.pl Finished, check the build log email for errors.\n";


  ##########################################
  ## Check Canonical Database for errors. ##
  ##########################################
  if ($email) {
    $wormbase->run_script("camcheck.pl -database ". $wormbase->database('camace'). "-e $email", $log) && die "Failed to run camcheck.pl\n";
  }
  else {  
    $wormbase->run_script("camcheck.pl -database ". $wormbase->database('camace'), $log) && die "Failed to run camcheck.pl\n";
  }
}

####################
#(3)Data dispersion#
####################

sub split_databases {

# Code changed so that all split databases are re-initialised prior to the canonical database being copied over the top of them, each split has it's own database.wrm file that contains the correct name for the split.  This then populated the top banner when the database is made.

  foreach my $database (@databases) {
    print "Destroying $database\n";
    $wormbase->run_command("rm -rf ".$wormpub."/camace_${database}/database/ACEDB.wrm", $log) && die "Failed to remove ".$wormpub."/camace_${database}/database/ACEDB.wrm\n";
    my $split_db = $wormpub."/camace_${database}";
    my $command = "y\nquit\n";
    open (TACE,"| $tace -tsuser merge_split $split_db") or die "Failed to open database connection\n";
    print TACE $command;
    close TACE;
    print "Transfering $canonical to $wormpub/camace_$database\n";
    $wormbase->run_script("TransferDB.pl -start $canonical -end $wormpub/camace_${database} -split -database -wspec", $log) && die "Failed to run TransferDB.pl for camace_${database}\n";
    }
  print "CAMACE SPLITS UPDATED\n";
  #remove gapped alignment for homol data from camace_gw3
  &loadace("/nfs/disk100/wormpub/camace_orig/acefiles/method_fix.ace", 'camace_gw3_method_fix') or die "Failed to updates the methods in camace_gw3!!\n";
}

sub usage {
  my $error = shift;
  if ($error eq "Help") {
    # Normal help menu
    system ('perldoc',$0);
    exit (0);
  }
}

__END__

=pod

=head2 NAME - merge_split_camaces

=head1 USAGE:

=over 4

=item merge_split_camaces [-options]

=back

merge_split_camaces is a wrapper with options to automate the merging of the
working split copies of camace, load the updates into the current version
of camace (with some additional housekeeping), and finally running the
TransferDB.pl jobs to (re)generate the working split copies of camace.

merge_split_camaces mandatory arguments:

=over 4

=item none

=back

merge_split_camaces optional arguments:

=over 4

=item -merge, Generate diff files from split camace databases
 
=item -update, Upload diff files to ~wormpub/DATABASES/camace and add BLAT, Locus data

=item -split, Transfer ~wormpub/DATABASES/camace into split camace databases

=item -help, Help page

=item -debug, Verbose/Debug mode

=back

=head1 RUN REQUIREMENTS:

=back

merge_split_camaces has been divorced from the /wormsrv2 disk

=head1 RUN OUTPUT:

=back

=head1 EXAMPLES:

=over 4

=item merge_split_camaces -merge -all 

=back

Dumps the relevant classes from camace_orig and the split databases, runs an
acediff to calculate the changes. This acediff file is then reformated to take
account of the acediff bug.

=head1 AUTHOR - Daniel Lawson

Email dl1@sanger.ac.uk

=cut
