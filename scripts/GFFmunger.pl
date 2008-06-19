#!/usr/local/bin/perl5.8.0 -w
#
# GFFmunger.pl
# 
# by Dan Lawson
#
# Last updated by: $Author: gw3 $
# Last updated on: $Date: 2008-06-19 13:00:11 $
#
# Usage GFFmunger.pl [-options]


#################################################################################
# variables                                                                     #
#################################################################################

use strict;                                      
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use Carp;
use Log_files;
use Storable;
use IO::Handle;
use Ace;

##################################################
# Script variables and command-line options      #
##################################################
my ($help, $debug, $test, $verbose, $store, $wormbase);

my $all;                       # All of the following:
my $landmark;                  #   Landmark genes
my $UTR;                       #   UTRs 
my $WBGene;                    #   WBGene spans
my $CDS;                       #   CDS overload
my $chrom;                     # single chromosome mode
my $datadir;
my $gffdir;
my $version;

GetOptions (
	    "all"       => \$all,
	    "landmark"  => \$landmark,
	    "UTR"       => \$UTR,
	    "CDS"       => \$CDS,
	    "chrom:s"   => \$chrom,
	    "gff:s"     => \$gffdir,
	    "splits:s"  => \$datadir,
	    "release:s" => \$version,
            "help"       => \$help,
            "debug=s"    => \$debug,
	    "test"       => \$test,
	    "verbose"    => \$verbose,
	    "store:s"      => \$store,
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


# get version number
my $WS_version;

if ($version) {
  $WS_version = $version;
} else {
  $WS_version = $wormbase->get_wormbase_version;
}



##############################
# Paths etc                  #
##############################

$datadir = $wormbase->gff_splits unless $datadir;
$gffdir  = $wormbase->gff        unless $gffdir;
my @gff_files;

# prepare array of file names and sort names

if (defined($chrom)){
    push(@gff_files,$chrom);
}
else {
    @gff_files = $wormbase->get_chromosome_names('-prefix' => 1, '-mito' => 1);
}

# check to see if full chromosome gff dump files exist
foreach my $file (@gff_files) {
    unless (-e "$gffdir/$file.gff") {
	&usage("No GFF file");
    }
    if (-e -z "$gffdir/$file.gff") {
	&usage("Zero length GFF file");
    }
}


my $addfile;
my $gffpath;


#################################################################################
# Main Loop                                                                     #
#################################################################################


if ($CDS || $all) {
  $log->write_to("# Overloading CDS lines\n");
  if (defined($chrom)){
    $log->write_to("overload_GFF_CDS_lines.pl -chrom $chrom -gff $gffdir\n");
    $wormbase->run_script("overload_GFF_CDS_lines.pl -chrom $chrom -gff $gffdir", $log); # generate *.CSHL.gff files
    
  } else {
    $log->write_to("overload_GFF_CDS_lines.pl -gff $gffdir\n");
    $wormbase->run_script("overload_GFF_CDS_lines.pl -gff $gffdir", $log);
  }
  foreach my $file (@gff_files) {
    next if ($file eq ""); 
    $gffpath = "$gffdir/${file}.gff";
    system ("mv -f $gffdir/$file.CSHL.gff $gffdir/$file.gff");        # copy *.CSHL.gff files back to *.gff name
  }

}

############################################################
# loop through each GFF file                               #
############################################################

foreach my $file (@gff_files) {

  next if ($file eq "");               # end loop if no filename
    
  $gffpath = "$gffdir/${file}.gff";

  $log->write_to("# File $file\n");
  
  if ($landmark || $all && $file ne "CHROMOSOME_MtDNA") {
    $log->write_to("# Adding ${file}_landmarks.gff file\n");
    $addfile = "$datadir/${file}_landmarks.gff";
    &addtoGFF($addfile,$gffpath);
  }

  if ($UTR || $all) {
    $log->write_to("# Adding ${file}_UTR.gff file\n");
    $addfile = "$datadir/${file}_UTR.gff";
    &addtoGFF($addfile,$gffpath);
  }
  
  $log->write_to("\n");
  
  unless ($file =~ (/MtDNA/)) {
    &check_its_worked($gffpath) if $all;
  }
}

##################
# Check the files
##################

foreach  my $file (@gff_files) {
  $wormbase->check_file("$gffdir/${file}.gff", $log,
                        minsize => 1500000,
                        lines => ['^##',
                                  "^$file\\s+\\S+\\s+\\S+\\s+\\d+\\s+\\d+\\s+\\S+\\s+[-+\\.]\\s+\\S+"],
                        );
}


# Tidy up
$log->mail();
print "Finished.\n" if ($verbose);
exit(0);



###############################
# subroutines                 #
###############################

sub check_its_worked {
	my $file = shift;
	my $landmark = qx{grep landmark $file | wc -l }; #qx{} captures system command output.
	my $fiveprime = qx{grep five_prime  $file | wc -l };
	my $partially = qx{grep Partially  $file | wc -l };
	
	my $msg;
	if ($landmark < 10) {
		$msg .= "landmark genes are not present\n";
	}
	if ( $fiveprime  < 10 ) {
		$msg .= "UTRs and are not present\n";
	}
	if ( $partially  < 10 ) {
		$msg .= "CDS overloading not present\n";
	}	
	
	if( defined ($msg) ) {
		$log->log_and_die("GFFmunging failed : $msg");
	}
	else {
		$log->write_to("GFFmunging appears to have worked\n");
	}
}

sub addtoGFF {
    
    my $addfile = shift;
    my $GFFfile = shift;
    
    system ("cat $addfile >> $GFFfile") && warn "ERROR: Failed to add $addfile to the main GFF file $GFFfile\n";

}


##########################################
sub usage {
  my $error = shift;

  if ($error eq "Help") {
    # Normal help menu
    system ('perldoc',$0);
    exit (0);
  }
  elsif ($error eq "No GFF file") {
      # No GFF file to work from
      print "One (or more) GFF files are absent from $gffdir\n\n";
      exit(0);
  }
  elsif ($error eq "Zero length GFF file") {
      # Zero length GFF file
      print "One (or more) GFF files are zero length. The GFF dump may not have worked\n\n";
      exit(0);
  }
  elsif ($error eq "Debug") {
    # No debug person named
    print "You haven't supplied your name\nI won't run in debug mode until I know who you are\n\n";
    exit (0);
  }
}

################################################
#
# Post-processing GFF routines
#
################################################



__DATA__
clone_path
CDS
WBGene
pseudogenes
transposon
rna
worm_genes
Coding_transcript
coding_exon
exon
exon_tRNA
exon_pseudogene
exon_noncoding
intron
intron_all
Genefinder
history
repeats
assembly_tags
TSL_site
polyA
oligos
RNAi
TEC_RED
SAGE
allele
clone_ends
PCR_products
cDNA_for_RNAi
BLAT_EST_BEST
BLAT_EST_OTHER
BLAT_OST_BEST
BLAT_OST_OTHER
BLAT_TRANSCRIPT_BEST
BLAT_mRNA_BEST
BLAT_mRNA_OTHER
BLAT_EMBL_BEST
BLAT_EMBL_OTHER
BLAT_NEMATODE
BLAT_NEMBASE
BLAT_TC1_BEST
BLAT_TC1_OTHER
BLAT_ncRNA_BEST
BLAT_ncRNA_OTHER
BLAT_WASHU
Expr_profile
BLASTX
WABA_BRIGGSAE
operon
Oligo_set
rest
__END__



=pod

=head2 NAME - GFFsplitter.pl

=back 

=head1 USAGE

=over 4

=item GFFsplitter.pl <options>

=back

This script splits the large GFF files produced during the build process into
smaller files based on a named set of database classes to be split into.
Output written to autoace/GFF_SPLITS/WSxx

=over 4

=item MANDATORY arguments: 

None.

=back

=over 4

=item OPTIONAL arguments: -help, this help page.

= item -debug <user>, only email report/logs to <user>

= item -archive, archives (gzips) older versions of GFF_SPLITS directory

= item -verbose, turn on extra output to screen to help track progress


=back


=head1 AUTHOR - Daniel Lawson

Email dl1@sanger.ac.uk

=cut
