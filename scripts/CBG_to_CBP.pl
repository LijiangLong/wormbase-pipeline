#!/software/bin/perl -w
#
# CBG_to_CBP.pl
# 
# by Gary Williams
#
# This takes a brigpep fasta file and convertes the entries to use
# the CBPxxx IDs instead of the CBGxxxx IDs
#
# Last updated by: $Author: gw3 $     
# Last updated on: $Date: 2008-01-09 10:34:09 $      

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

######################################
# variables and command-line options # 
######################################

my ($help, $debug, $test, $verbose, $store, $wormbase);
my ($input);

GetOptions ("help"       => \$help,
            "debug=s"    => \$debug,
	    "test"       => \$test,
	    "verbose"    => \$verbose,
	    "store:s"    => \$store,
	    "input:s"    => \$input,
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


##########################
# MAIN BODY OF SCRIPT
##########################

my $output = "$input.new";

open (IN, "< $input") || $log->log_and_die("cant open $input: $!\n");
open (OUT, "> $output") || $log->log_and_die("cant open $output: $!\n");

while (my $line = <IN>) {
  chomp $line;
  if ($line =~ /^>/) {
    if ($line !~ /^>CBP\S+/) {
      my ($id) = ($line =~ /(CBP\S+)/);
      print OUT ">$id\n";
    } else {			# the title is OK, just print it
      print OUT "$line\n";
    }
  } else {
    print OUT "$line\n";
  }
}

close(OUT);
close(IN);

$wormbase->run_command("mv -f $output $input", $log);

$wormbase->check_file($input, $log,
		      minsize => 5000000,
		      maxsize => 20000000,
# every line must either be a >CBP title or not a title, ie all titles
# must be CBP
		      lines => ['^>CBP\S+', '^[^>]'], 
		      );

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
