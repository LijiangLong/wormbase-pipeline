#!/usr/local/bin/perl5.8.0 -w
#
# remap_fosmids_between_releases.pl                     
# 
# by Gary Williams                         
#
# This takes the BUILD_DATA/MISC_DYNAMIC/fosmids.ace file and converts any coordinates that have changed between releases
#
# Last updated by: $Author: klh $     
# Last updated on: $Date: 2012-06-22 08:56:53 $      

use strict;                                      
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use Carp;
use Log_files;
use Storable;
#use Ace;
#use Sequence_extract;
#use Coords_converter;

use Modules::Remap_Sequence_Change;

######################################
# variables and command-line options # 
######################################

my ($help, $debug, $test, $verbose, $store, $wormbase);
my ($input, $output);

GetOptions ("help"       => \$help,
            "debug=s"    => \$debug,
	    "test"       => \$test,
	    "verbose"    => \$verbose,
	    "store:s"    => \$store,
            "input:s"    => \$input,
	    "output:s"   => \$output,
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

# Set up top level base directories (these are different if in test mode)
my $ace_dir         = $wormbase->autoace;     # AUTOACE DATABASE DIR

# some database paths
my $currentdb = $wormbase->database('current');

##########################
# read in the mapping data
##########################

my $version = $wormbase->get_wormbase_version;
print "Getting mapping data for WS$version\n";
my $assembly_mapper = Remap_Sequence_Change->new($version - 1, $version, $wormbase->species, $wormbase->genome_diffs);

##########################
# MAIN BODY OF SCRIPT
##########################


#
# Read the FOSMIDS locations from the previous ace file
# in order to be able to remap them
#


#Sequence : "SUPERLINK_RW5"
#Genomic_non_canonical "WRM0638bH09" 4298005   4332968
# 
#Sequence : "WRM0638bH09"
#Method Vancouver_fosmid
#Species "Caenorhabditis elegans"
#From_laboratory "VC"
#Interpolated_map_position V -5.737084
# 
#Sequence : "Y75B8A"
#Genomic_non_canonical "WRM0637cG02" 15107   46049
# 
#Sequence : "WRM0637cG02"
#Method Vancouver_fosmid
#Species "Caenorhabditis elegans"
#From_laboratory "VC"
#Interpolated_map_position III 15.199464


# start the coords converters
my $current_converter = Coords_converter->invoke($currentdb, 0, $wormbase);
my $autoace_converter = Coords_converter->invoke($ace_dir, 0, $wormbase);

# get the FOSMIDS details
my $clone_id;
my ($indel, $change);
my $sequence_flag=1;		# counts which sequence line we are looking at, Fosmid or Superlink

open (IN, "< $input") || die "can't open input file $input\n";
open (OUT, "> $output") || die "can't open output file $output\n";
while (my $line = <IN>) {
  chomp $line;

  if ($line =~ /Sequence\s+:\s+\"(\S+)\"/) { # we want every other Sequence line
    if ($sequence_flag) {
      $clone_id = $1;
      print "Got superlink/clone: $clone_id\n" if ($verbose);
      $sequence_flag = 0;
    } else {
      print OUT "$line\n";
      $sequence_flag = 1;	# next time we will have the Sequence line we want
    }

  } elsif ($line =~ /Genomic_non_canonical\s+(\S+)\s+(\d+)\s+(\d+)/) {
    my ($fosmid_id, $start, $end) = ($1, $2, $3);
    print "$line\n" if ($verbose);

    # if $start > $end, then sense is -ve (i.e. normal ace convention)
    ($clone_id, $start, $end, $indel, $change) = 
	$assembly_mapper->remap_clone($clone_id, $start, $end, $current_converter, $autoace_converter);

    if ($indel) {
      $log->write_to("There is an indel in the sequence in FOSMID $fosmid_id, clone $clone_id, $start, $end\n");
    } elsif ($change) {
      $log->write_to("There is a change in the sequence in FOSMID $fosmid_id, clone $clone_id, $start, $end\n");
    }

    print "Genomic_non_canonical $fosmid_id $start $end\n" if ($verbose);
    print OUT "Sequence : \"$clone_id\"\n";
    print OUT "Genomic_non_canonical $fosmid_id $start   $end\n";

  } else {
    print OUT "$line\n";
  }

}
close (IN);
close (OUT);


# Close log files and exit
$log->mail();
print "Finished.\n" if ($verbose);
exit(0);






##############################################################
#
# Subroutines
#
##############################################################



##########################################

sub usage {
  my $error = shift;

  if ($error eq "Help") {
    # Normal help menu
    system ('perldoc',$0);
    exit (0);
  }
}

##########################################




# Add perl documentation in POD format
# This should expand on your brief description above and 
# add details of any options that can be used with the program.  
# Such documentation can be viewed using the perldoc command.


__END__

=pod

=head2 NAME - script_template.pl

=head1 USAGE

=over 4

=item script_template.pl  [-options]

=back

This script does...blah blah blah

script_template.pl MANDATORY arguments:

=over 4

=item None at present.

=back

script_template.pl  OPTIONAL arguments:

=over 4

=item -h, Help

=back

=over 4
 
=item -debug, Debug mode, set this to the username who should receive the emailed log messages. The default is that everyone in the group receives them.
 
=back

=over 4

=item -test, Test mode, run the script, but don't change anything.

=back

=over 4
    
=item -verbose, output lots of chatty test messages

=back


=head1 REQUIREMENTS

=over 4

=item None at present.

=back

=head1 AUTHOR

=over 4

=item Keith Bradnam (krb@sanger.ac.uk)

=back

=cut
