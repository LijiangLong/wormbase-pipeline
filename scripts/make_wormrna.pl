#!/usr/local/bin/perl5.8.0 -w
#
# make_wormrna.pl
# 
# Usage : make_wormrna.pl -r <release_number>
#
# Builds a wormrna data set from the current autoace database
#
# Last updated by: $Author: gw3 $
# Last updated on: $Date: 2008-12-12 14:43:26 $


#################################################################################
# variables                                                                     #
#################################################################################

use strict;
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use IO::Handle;
use Ace;
use Socket;
use Storable;

    
######################################
# variables and command-line options # 
######################################

my ($help, $debug, $release, $test, $store, $species);
my $errors      = 0;    # for tracking how many errors there are

GetOptions (
	    "help"      => \$help,
	    "release=s" => \$release,
            "debug=s"   => \$debug,
	    "test"      => \$test,
	    "store:s"   => \$store,
	    "species:s" => \$species
	   );

my $wormbase;
if( $store ) {
  $wormbase = retrieve( $store ) or croak("cant restore wormbase from $store\n");
}
else {
  $wormbase = Wormbase->new( -debug   => $debug,
			     -test    => $test,
			    -organism => $species
			   );
}

my $log = Log_files->make_build_log($wormbase);

# Display help if required
&usage("Help") if ($help);


#######################################
# release data                        #
#######################################

$release         = $wormbase->get_wormbase_version unless $release;
my $old_release  = $release-1;

my $dbdir     = $wormbase->autoace;
my $new_wrdir = $wormbase->wormrna;
my $tace      = $wormbase->tace;

$ENV{'ACEDB'} = $dbdir;

###############################################
# retrieve the desired RNA sequence objects   #
###############################################

my $db = Ace->connect (-path => $dbdir, -program => $tace) || $log->log_and_die("Couldn't connect to $dbdir\n");
# Get RNA genes, but not other Transcript objects
my $query = "FIND Transcript WHERE Method != Coding_transcript AND Method != History AND Species = \"".$wormbase->full_name."\"";
$log->write_to("$query\n");
my @transcripts = $db->fetch (-query => $query); #Filtered composite Transcripts(NOT Method = Coding_transcript/history/non_coding_transcript).

my $count = scalar(@transcripts);
$log->write_to("Finding ". $count . " RNA sequences, writing output file\n\n");


###########################################################################
# get the rna sequence, write a rna.fasta file,
###########################################################################
my $rnafile = "$new_wrdir/".$wormbase->pepdir_prefix."rna$release.rna";
open (DNA , ">$rnafile") || die "Couldn't write $rnafile : $!\n"; 
my (%dot2num , @dotnames , @c_dotnames);

foreach my $transcript (@transcripts) {    
  undef (my $dna);
  undef (my $cgc_name);
  undef (my $brief_id);
  undef (my $method);
  undef (my $gene);
    
  my $obj = $db->fetch(Transcript=>"$transcript");
  

  # Grab Brief_identification
  $brief_id = $obj->Brief_identification;
  if ((!defined ($brief_id)) || ($brief_id eq "")) {
    $log->write_to("ERROR: No Brief_id for $transcript\n");
    $log->error;
    undef ($brief_id);
  }
  
  $dna = $obj->asDNA();
  if ((!defined ($dna)) || ($dna eq "")) {
    $log->error("ERROR: cannot extract dna sequence for $transcript\n");
    # can't include in WormRNA if there is no DNA!
    next; 
  }
  $dna =~ s/\n//;
  $dna =~ /^>(\S+)\s+(\w.*)/s; 
  my $dseq = $2; 
  $dseq =~ tr/a-z/A-Z/; 
  $dseq =~ tr /T/U/; 
  $dseq =~ s/\s//g;
  
  # Grab locus name if present
  $gene = $obj->Gene;
  $cgc_name = $gene->CGC_name if (defined $gene);
  

  my $rseq = &reformat($dseq);
  if ($cgc_name) {
    print DNA ">$transcript $brief_id locus:$cgc_name\n$rseq";
  }
  elsif($brief_id) {
    print DNA ">$transcript $brief_id\n$rseq";
  }
  else{
    print DNA ">$transcript\n$rseq";
  }
  
  $obj->DESTROY();
  
}   

close DNA;
chmod (0444 , $rnafile) || $log->write_to("cannot chmod $rnafile\n");


###########################################################################
# Create the associated README file          
###########################################################################

open (README , ">$new_wrdir/README") || $log->log_and_die("Couldn't creat README file\n"); 
my $orgname = $wormbase->full_name('-short' => 1);
my $readme = <<END;
WormRNA
-------
WormRNA is an additional database that accompanies the main WormBase 
database (see http://www.wormbase.org for more details) and simply comprises
the sequences of all known non-coding RNA molecules in the $orgname genome.  

This release (WormRNA$release) corresponds to release WS$release of WormBase.
The accompanying file (wormrna$release.rna) contains $count RNA sequences in FASTA
format.

WormBase group, Sanger Institute

END

print README "$readme";


##################
# Tidy up
##################

close(README);
$db->close;

##################
# Check the files
##################

$wormbase->check_file("$new_wrdir/README", $log,
minsize => 400,
maxsize => 500,
);
$wormbase->check_file($rnafile, $log,
readonly => 1,
minsize => 400000,
maxsize => 1200000,
lines => ['^>\S+\.\S+\s+\S+', '^[ACGU]+$', '^$']
);

$log->mail;
exit(0);




##############################################################
#
# Subroutines
#
##############################################################


sub reformat {
    my $in_string = shift;
    my $out_string = "";

    my $string_len = length ($in_string);
    my $lines = int ($string_len / 60) ;

    for (my $i = 0; $i <= $lines; $i++) {
	$out_string = $out_string . substr($in_string,($i*60),60) . "\n";
    }
    return ($out_string);
}



#################################

sub usage {
  my $error = shift;

  if ($error eq "Help") {
    # Normal help menu
    system ('perldoc',$0);
    exit (0);
  }
  # Error  2 - invalid wormrna release number
  elsif ($error eq "releasename") {
    # Invalid wormrna release number file
    print "=> Invalid/missing wormrna release number supplied.\n";
    print "=> Release number must be an interger (e.g. 30)\n\n";
    exit(0);
  }

}




__END__

=pod

=head2   NAME - make_wormrna.pl


=head1 USAGE

=over 4

=item make_wormrna.pl [-options]

=back

make_wormrna.pl will generate a rna data set from the autoace
database directory.  Finds RNA genes in Transcript class, but filters out 
any other Transcript objects which represent full length transcripts of
coding genes (i.e. where Method = Transcript)

make_wormrna.pl mandatory arguments:

=over 4

=item -release <release number>

=back

make_wormrna.pl OPTIONAL arguments:

=over 4

=item -help, Help page

=item -debug <username> = Verbose/Debug mode

=back

=head1 EXAMPLES:

=over 4

=item make_wormrna.pl -release 4

=back

Creates a new wormrna data set in the (new) /wormsrv2/WORMRNA/wormrna4 directory

=cut




















