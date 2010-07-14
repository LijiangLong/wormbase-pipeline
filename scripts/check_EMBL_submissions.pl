#!/software/bin/perl -w
#
# check_EMBL_submissions.pl
# dl
#
# Checks the return mail from the EBI against the list of submitted
# clones. Entries which have failed to load or return are highlighted
# and changes in sequence version are notified.

# Last updated on: $Date: 2010-07-14 14:50:34 $
# Last updated by: $Author: pad $

use strict;
use Getopt::Long;
use IO::Handle;
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Log_files;
use Storable;

my ($embl_file,$maintainer,$wormbase,$store,$test,$load);

##############################
# command-line options       #
##############################

my $debug;                 # Debug option
my $help;                  # Help menu
my $file;                  # EMBL file
my $database;              # specify full path to alternate reference database.
my $verbose;

GetOptions (
            "debug:s"    => \$debug,
            "help"       => \$help,
	    "file:s"     => \$embl_file,
	    "store:s"    => \$store,
	    "verbose"    => \$verbose,
            "test"       => \$test,
	    "database:s" => \$database,
	    "load"       => \$load
	   );

 ########################################
 # Script variables (run)               #
 ########################################

if( $store ) {
  $wormbase = retrieve( $store ) or croak("cant restore wormbase from $store\n");
}
else {
  $wormbase = Wormbase->new( -debug   => $debug,
			     -test    => $test,
                           );
}

if (!defined $debug) {
    my $maintainer = "All";
  }
else {
  $maintainer = $debug;
}

#"/nfs/wormpub/logs/check_EMBL_submissions.$rundate.$$";

 ########################################
 # Paths/variables etc                  #
 ########################################

my $dbdir;

if (defined$database) {
    $dbdir = $database;
}
else {
    $dbdir = glob "/nfs/wormpub/DATABASES/camace";
}
&usage(5) if !(-e "$dbdir/database/ACEDB.wrm");
my $base_dir = $wormbase->wormpub;
my $tace = $wormbase->tace;
my $submitted_file = $base_dir."/analysis/TO_SUBMIT/submitted_to_EMBL";
my (%clone2id,%id2sv,%embl_acc,%embl_status,%embl_sv);
my $out_file = $base_dir."/analysis/TO_SUBMIT/SV_update.ace";
my $errors1 = 0;
my $errors2 = 0;
my $errors3 = 0;
my $updates = 0;
my $loaded = 0;
my @prob_clones;

 ########################################
 # simple consistency checks            #
 ########################################

&usage(0) if ($help);
&usage(1) unless (-e $embl_file);
&usage(2) unless (-e $submitted_file);

 ########################################
 # Open logfile and out_put file         #
 ########################################

&usage(3) if (-e $out_file);
open (OUT, ">$out_file") or die "Cannot open output file $out_file\n";

my $log= Log_files->make_build_log($wormbase);
$log->write_to("# check_EMBL_submissions\n\n");
$log->write_to("# run details    : ".$wormbase->rundate.".".$wormbase->runtime."\n");
$log->write_to("\n");

 ########################################
 # query autoace for EMBL ID/AC lines   #
 ########################################
$ENV{'ACEDB'} = $dbdir;
my $def = "$dbdir/wquery/SCRIPT:check_EMBL_submissions.def";
&usage(4) if !(-e "$def");

my $command = "Table-maker -p $def\nquit\n";
my ($sv,$id,$name);

open (TACE, "echo '$command' | $tace | ");
while (<TACE>) {
  s/acedb\> //g;
  print "$_\n" if ($verbose);
  chomp;
  next if ($_ eq "");
  next if (/\/\//);

  s/\"//g;
  if (/(\S+)\s+(\S+).(\d+)/) {
    ($clone2id{$1} = $2); # ACEDB_clone => NDB_ID  	
    $id   = $2;
    $sv   = $3;
    $name = $1;
    ($id2sv{$id} = $sv);
  }
}
close TACE;

$log->write_to("Populated hashes with data for " . scalar (keys %clone2id) . " clones\n\n");

 ########################################
 # returned entries from EMBL           #
 ########################################

open (EMBL, "<$embl_file") || die "Cannot open EMBL returns\n";
while (<EMBL>) {
  chomp;
  print "$_\n" if ($verbose);
  # Z81068         Z81068           -                                              Finished   1
if ($_ =~ /^(\S+)\s+(\S+)\s+\-\s+(\S+)\s+(\d+)/) {
    $embl_acc{$1}    = $2;
    $embl_status{$1} = $3;
    $embl_sv{$1}     = $4;
    print "EMBL_AC:$2\nEMBL_Status:$3\nEMBL_SV:$4\n" if ($verbose);
    print "processed $1\n" if ($debug);
    next;
  }
  # Entries that haven't loaded for some reason.
  elsif ($_ =~ /^(\S+)\s+(\S+)\s+\-\s+(\S+\s\S+)\s+(-)/) {
    $embl_acc{$1}    = $2;
    $embl_status{$1} = $3;
    $embl_sv{$1}     = undef;
    print "EMBL_AC:$2\nEMBL_Status:$3\nEMBL_SV:$4\n" if ($verbose);
    print "processed $1\n" if ($debug);
    next;
  }
  # EMBL lines with hidden tokens
  # 0  'CU457739       CU457739         _AF043691                                      Finished   1'
  elsif ($_ =~ /^(\S+)\s+(\S+)\s+\S+\s+(\S+)\s+(\d+)/) {
    $embl_acc{$1}    = $2;
    $embl_status{$1} = $3;
    $embl_sv{$1}     = $4;
    print "EMBL_AC:$2\nEMBL_Status:$3\nEMBL_SV:$4\n" if ($verbose);
    print "processed $1\n" if ($debug);
    next;
  }
}

$log->write_to("Populated hashes with data for " . scalar (keys %embl_status) . " entries\n\n\n");
print ("Populated hashes with data for " . scalar (keys %embl_status) . " entries\n\n\n") if ($debug);

 #############################################################
 # submitted clones from ~wormpub/analysis/TO_SUBMIT         #
 #############################################################

 
open (SUBMITTED, "<$submitted_file") || die "Cannot open submit_TO_SUBMIT log file\n";;
while (<SUBMITTED>) {
  ($name) = (/^(\S+)\.\d+.embl/);
  if (!defined $clone2id{$name}) {$log->write_to("eek .. no ID for clone $name\n");}
  $id = $clone2id{$name};
  $log->write_to("# $name   \tSubmitted_to_EMBL - ");
  if (!defined $embl_status{$id}) {
    $log->write_to("not returned\n");
    $errors1++;
    next;
  }
  elsif ($embl_status{$id} eq "Finished") {
    $log->write_to("loaded  \t");
    $loaded++;
  }
  elsif ($embl_status{$id} eq "Not\ Loaded") {
    $log->write_to("***failed to load***\t\n");
    push (@prob_clones,"$name");
    $errors2++;
    next;
  }
  elsif ($embl_status{$id} ne "Finished" or" Not_Loaded") {
    $log->write_to("***unknown status ($embl_status{$id})***\n");
    $errors3++;
    next;
  }
  if (defined $embl_sv{$id} && $embl_sv{$id} ne $id2sv{$id}) {
    $log->write_to("Update sequence version CAM:$id2sv{$id} EMBL:$embl_sv{$id}\n");

    print OUT "Sequence : \"$name\"\n-D Database  EMBL  NDB_SV\n\nSequence : \"$name\"\nDatabase  EMBL  NDB_SV  $id.$embl_sv{$id}\n\n";
    $updates++;
    next
  }
  else {
    $log->write_to("SV unchanged $embl_sv{$id}:$id2sv{$id}\n");
  }
}
$log->write_to("--------------------------------------------------------------------\n$loaded clones loaded successfully\n");
$log->write_to("$updates clone(s) have an new SV from EMBL\n");
$log->write_to("$errors1 clones were not returned\n");
$log->write_to("$errors2 clones Failed to load\n");
$log->write_to("$errors3 clones returned with an incorrect error code?\n--------------------------------------------------------------------\n\n");
$log->write_to("Problem_clones: @prob_clones\n");
foreach my $prob_clone(@prob_clones){
  $wormbase->run_command("gunzip /lustre/cbi4/work1/wormpub/analysis/TO_SUBMIT/${prob_clone}*", $log);
}

close OUT;

if (defined$load) {
# load information to $database if -load is specified
#$wormbase->load_to_database($dbdir, $out_file, 'check_EMBL_submission.pl', $log, undef, 1);
$wormbase->load_to_database($wormbase->database('camace'), $out_file, 'check_EMBL_submission.pl', $log);
$log->write_to("\n\nThe update file $out_file has been loaded into $dbdir\n\n");
}
else {
$log->write_to("\n\nThe update file $out_file needs to be loaded into camace") if ($updates > 0);
}

$log->write_to("check_EMBL_submissions.pl has Finished.\nUpdated sequence version info can be found here -> $out_file\n");

###############################
# Mail log to curator         #
###############################
$log->mail($maintainer);

#Tidy-up#
close EMBL;
close SUBMITTED;
exit(0);

##############################
#        Subroutines         #
##############################

sub usage {
    my $error = shift;
    if ($error == 0) {
        exec ('perldoc',$0);
        exit (0);
    }
    # Error  1 - EMBL return filename is not valid
    elsif ($error == 1) {
	print "The EMBL return summary file does not exist\n\n";
        exit(0);
    }
    # Error  2 - submitted_to_EMBL file is not present
    elsif ($error == 2) {
	print "The submitted_to_EMBL summary file does not exist\n\n";
        exit(0);
    }
    elsif ($error == 3) {
      print "\nERROR: Output file $out_file already exists!\nPlease specify a file name - e.g. SV_update_". $wormbase->rundate. ".ace\n\n[INPUT]:";
      my $tmp = <STDIN>;
      $out_file = $base_dir."/analysis/TO_SUBMIT/$tmp";
    }
    elsif ($error == 4) {
      print "ERROR: Table-maker $dbdir/wquery/SCRIPT:check_EMBL_submissions.def does not exist!\n\nDo you want to default to the canonical camace version of the definition?......yes/no\n\n[INPUT]:";
      my $tmp2 = <STDIN>;
      chomp $tmp2;
      if ($tmp2 =~ "yes") {
      $def = $base_dir."/DATABASES/camace/wquery/SCRIPT:check_EMBL_submissions.def";
    }
      elsif ($tmp2 =~ "no"){
	die "ERROR: Alternate .def file not accepted!!!\n";
      }
      else {print "ERROR: $tmp2 is not a valid response......Aborting\n";
	    die;
	  }
    }
    elsif ($error == 5) {
      print "ERROR: The database: $dbdir does not exist, please Quit or Specify a new database\n\nquit/database path\n\n[INPUT]:";
      my $tmp3 = <STDIN>;
      chomp $tmp3;
      if ($tmp3 =~ "quit") {
	die "Aborted.......\n\n";
      }
      else {
	$dbdir = "$tmp3";
      }
    }
  }


__END__

=pod

=head2 NAME - check_EMBL_submissions.pl

=head1 USAGE:

=over 4

=item check_EMBL_submissions.pl

=back

check_EMBL_submissions.pl correlates the returned summary e-mail from the EBI
with the list of clone submitted by submit_TO_SUBMIT. The output will highlight
which entries are unaccounted for and whether the sequence version field has
changed.

check_EMBL_submissions.pl mandatory arguments:

=over 4

=item -file <filename>, EMBL summary e-mail (exported from Pine/Mozilla mail)

=back

check_EMBL_submissions.pl optional arguments:

=over 4

=item -help, Help page

=item -debug, Verbose/Debug mode


=back

=head1 RUN REQUIREMENTS:

=back

The submitted_to_EMBL file produced by the submit_TO_SUBMIT script is needed
as reference for the entries submitted to the EBI.

=head1 RUN OUTPUT:

=back

The emailed log file contains the output from the script. 
An example of this output is given below:

VY10G11R   	Submitted_to_EMBL - loaded  	SV unchanged 1:1
Y105E8A   	Submitted_to_EMBL - loaded  	Update sequence version CAM:4 EMBL:5
Y115F2A         Submitted_to_EMBL - ***failed to load***
Y57G11C   	Submitted_to_EMBL - not returned
Y45F10A   	Submitted_to_EMBL - ***unknown status (<value>)***
--------------------------------------------------------------------
2 clones loaded successfully
1 clone(s) have an new SV from EMBL
1 clone(s) were not returned
1 clone(s) Failed to load
1 clone(s) returned with an incorrect error code?
--------------------------------------------------------------------

=head1 EXAMPLES:

=over 4

check_EMBL_submissions.pl -file /nfs/griffin2/dl1/EMBL_020123

=head1 AUTHOR: 

Daniel Lawson

Email dl1@sanger.ac.uk

=cut




