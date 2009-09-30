#!/usr/local/bin/perl5.8.0 -w
#
# GetPFAM_motifs.pl 
# 
# by Anthony Rogers
#
# Gets latest PFAM motifs from sanger/pub and puts info in to ace file
#
# Last updated by: $Author: ar2 $                      
# Last updated on: $Date: 2009-09-30 10:05:48 $         

use strict;                                      
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use Carp;
use Log_files;
use Storable;


######################################
# variables and command-line options # 
######################################

my ($help, $debug, $test, $verbose, $store, $wormbase);

my $load;      # option for loading resulting acefile to autoace

GetOptions ("help"       => \$help,
            "debug=s"    => \$debug,
	    "test"       => \$test,
	    "verbose"    => \$verbose,
	    "store:s"      => \$store,
	    "load"       => \$load,
            );


if ( $store ) {
  $wormbase = retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug   => $debug,
                             -test    => $test,
			     );
}

# Display help if required
&usage("Help") if ($help);

# in test mode?
if ($test) {
  print "In test mode\n" if ($verbose);

}

# establish log file.
my $log = Log_files->make_build_log($wormbase);

#################################
# Set up some useful paths      #
#################################

my $ace_dir         = $wormbase->autoace;     # AUTOACE DATABASE DIR

my $rundate         = $wormbase->rundate;
my $runtime         = $wormbase->runtime;






#Get the latest version
my $pfam_motifs_gz = "/tmp/Pfam_motifs.".$wormbase->species.".gz";
$log->write_to("Attempting to wget the latest version\n");
print "Attempting to wget the latest version\n";
`wget -q -O $pfam_motifs_gz ftp://ftp.sanger.ac.uk/pub/databases/Pfam/current_release/Pfam-A.full.gz` and die "$0 Couldnt get Pfam-A.full.gz \n";

`gunzip -f $pfam_motifs_gz` and die "gunzip failed\n";

my $pfam_motifs = "/tmp/Pfam_motifs.".$wormbase->species;
$log->write_to("Opening file $pfam_motifs\n");
print "\n\nOpening file $pfam_motifs . . \n";
open (PFAM,"<$pfam_motifs") or die "cant open $pfam_motifs\n";


my $acefile = "$ace_dir/acefiles/pfam_motifs.ace";

open (PFAMOUT,">$acefile") or die "cant write to $ace_dir/acefiles/pfam_motifs.ace\n";

my $text;
my $pfam;

print "\treading data . . . \n";
my $pfcount = 0;
while (<PFAM>){
  chomp;
  if ($_ =~ /^\/\//){
    if (defined $pfam){
      $pfcount++;
      print PFAMOUT "Motif : \"PFAM:$pfam\"\n";
      print PFAMOUT "Title \"$text\"\n";
      print PFAMOUT "Database \"Pfam\" \"Pfam_ID\" \"$pfam\"\n";
      print PFAMOUT "\n";
      undef $pfam;
      $text = "";
    }
    else{
       die "gone through a record without picking up pfam\n";
    }
  }
  #get the id
  if($_ =~ m/^\#=GF AC\s+(PF\d{5})/  ){ 
    $pfam = $1;
  }
  
  #get the description
  if($_ =~ m/^\#=GF DE\s+(.*$)/  ) {
    $text = $1;
    $text =~ s/\"//g;
  }         
 }
  
$log->write_to("added $pfcount PFAM motifs\n");

print "finished at ",`date`,"\n";
close PFAM;
close PFAMOUT;

# load file to autoace if -load specified
  $wormbase->load_to_database($wormbase->autoace, "$ace_dir/acefiles/pfam_motifs.ace", 'pfam_motifs', $log) if($load);

# tidy up and exit
  $wormbase->run_command("rm $pfam_motifs",$log);
$log->mail();
print "Finished.\n" if ($verbose);
exit(0);


##############################################################
#
# Subroutines
#
################################################################


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

=head2 NAME GetPFAM_motifs.pl

=head1 USAGE

=over 4

=item GetPFAM_motifs.pl

=back

This script:

wgets the latest version of ftp.sanger.ac.uk/pub/databases/Pfam/Pfam-A.full.gz
unzips it then parses it to produce an ace file of format

Motif : "PFAM:PF00351"

Title "Biopterin-dependent aromatic amino acid hydroxylase"

Database" "Pfam" "Pfam_ID" "PF00351"


writes to ~wormpub/BUILD_DATA/MISC_DYNAMIC/misc_pfam_motifs.ace

=head4 OPTIONAL arguments:

=over 4
  
=item -load
 
if specified will load resulting acefile to autoace
 
=back
 

=head1 REQUIREMENTS

=over 4

=item This script must run on a machine which can see the /wormsrv2 disk.

=back

=head1 AUTHOR

=over 4

=item Anthony Rogers (ar2@sanger.ac.uk)

=back

=cut
