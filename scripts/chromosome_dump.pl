#!/software/bin/perl -w
#!/usr/local/bin/perl5.8.0 -w
#
# chromosome_dump.pl 
#
# by Keith Bradnam
#
# A script for dumping dna and/or gff files for chromosome objects in autoace
# see pod for more details
#
# Last updated by: $Author: ar2 $
# Last updated on: $Date: 2008-10-10 09:38:54 $


use strict;
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use IO::Handle;
use Log_files;
use Storable;


######################################################
# Script variables and command-line options          #
######################################################

our ($help, $debug, $dna, $gff, $zipdna, $zipgff, $composition, $database, $dump_dir, $test, $quicktest);
my $store;

GetOptions ("help"        => \$help,
            "debug=s"     => \$debug,
	    "dna"         => \$dna,
	    "gff"         => \$gff,
	    "zipdna"      => \$zipdna,
	    "zipgff"      => \$zipgff,
	    "composition" => \$composition,
	    "database=s"  => \$database,
	    "dump_dir=s"  => \$dump_dir,
	    "test"        => \$test,
	    "quicktest"   => \$quicktest,
	    "store:s"     => \$store
	   );

my $wormbase;
$test = 1 if $quicktest;
if( $store ) {
  $wormbase = retrieve( $store ) or croak("cant restore wormbase from $store\n");
}
else {
  $wormbase = Wormbase->new( -debug   => $debug,
			     -test    => $test,
			   );
}

our $tace   = $wormbase->tace;
our $giface = $wormbase->giface;

##########################################################

# Display help if required
&usage("Help") if ($help);

# Sanity checks
#if($database && !$dump_dir){
#  die "You have specified a database (-database flag) but not a destination directory\nto dump to (-dump_dir flag).\n";
#}
if(!$database && $dump_dir){
  die "You have specified a destination directory to dump to (-dump_dir flag) but not\na source database (-database flag).\n";
}
if(!$gff && !$dna && !$composition && !$zipgff && !$zipdna){
  die "No major option (-dna, -gff, -composition, -zipdna, or -zipgff) has been specified, try again\n";
}

# Set up top level base directory which is different if in test mode
# Make all other directories relative to this
my $basedir   = $wormbase->basedir;
$database = $wormbase->autoace     unless ($database);
$dump_dir = $wormbase->chromosomes unless ($dump_dir);


#####################################################
# Main subroutines
#####################################################

# establish log file.
my $log = Log_files->make_build_log($wormbase);

&dump_dna    if ($dna);
&composition if ($composition);
&zip_files   if ($zipdna || $zipgff);

# say goodnight Barry
$log->mail;

exit(0);




#############################################################################
# Subroutines
#############################################################################


#########################
# dump dna files
#########################

sub dump_dna {

  my $command;

  # command generation
  if($quicktest) {
   $command = "find sequence CHROMOSOME_III\ndna -f $dump_dir/CHROMOSOME_III.dna\n";
  }
  else {
    foreach my $c ($wormbase->get_chromosome_names(-mito => 1,-prefix=> 1)) {
      $command.="find sequence $c\ndna -f $dump_dir/$c.dna\n";
    }
  }
  $command.='quit';

  &execute_ace_command($command,$tace,$database);

  $log->write_to("Removing blank first lines\n");
  foreach ($wormbase->get_chromosome_names(-mito => 1,-prefix=> 1)) {
    $wormbase->remove_blank_lines("$dump_dir/$_.dna", 'no_log');
  }
  if ($wormbase->assembly_type eq 'contig') {
    unlink "$dump_dir/supercontigs.fa" if -e "$dump_dir/supercontigs.fa";
    foreach ($wormbase->get_chromosome_names(-mito => 1,-prefix=> 1)) {
	    $wormbase->run_command("cat $dump_dir/$_.dna >> $dump_dir/supercontigs.fa",'no_log');
    }
  }
  $log->write_to("Finished dumping DNA\n\n");
}



#########################
# dump gff files
#########################

sub dump_gff {

 my $command;
 if($quicktest) {
	 $command = "gif seqget CHROMOSOME_III ; seqfeatures -version 2 -file $dump_dir/CHROMOSOME_III.gff";
 }
 else {
	foreach my $c ($wormbase->get_chromosome_names(-mito => 1,-prefix=> 1)) {
		$command.="gif seqget $c ; seqfeatures -version 2 -file $dump_dir/$c.gff\n"; # a bit iffy, as it does a memcopy for every .=
  	}
 }
 $command.='quit';

  &execute_ace_command($command,$giface,$database);
  $log->write_to("Finished dumping GFF files\n\n");
}


###################################
# produce dna composition files
###################################

sub composition {

  $log->write_to("Generating composition.all\n");	

  chdir $dump_dir;
  
  my @chroms = $quicktest? qw(III) : $wormbase->get_chromosome_names();
  my $prefix= $wormbase->chromosome_prefix();

  my $total;
  my $ns;
  my $gaps;
  my $as;
  my $cs;
  my $gs;
  my $ts;

  $log->write_to("Generating totals file\n");

  foreach my $chr (@chroms) {

    my $file = "$dump_dir/$prefix"."$chr.dna";

    #print "read $file\n";
    my $seq = &read_chromosome($file);

    my ($a, $c, $g, $t, $gap, $n, $length_dna) = &get_composition($seq);
    $as += $a;
    $cs += $c;
    $gs += $g;
    $ts += $t;
    $total += $length_dna;
    $ns += $n;
    $gaps += $gap;
  }

  open(OUT, ">$dump_dir/composition.all") or $log->log_and_die("Couldn't open composition.all\n");
  print OUT " $total total\n";
  print OUT " a $as\n";
  print OUT " c $cs\n";
  print OUT " g $gs\n";
  print OUT " t $ts\n";
  print OUT " - $gaps\n";
  print OUT " n $ns\n";
  close(OUT);

  my $final_total = $total - $gaps;

  $wormbase->run_command("echo $total $final_total > totals",$log);
  $wormbase->release_composition($log);
}

##########################################
# get the composition of a sequence

sub get_composition {
  my ($dna) = @_;

  my ($a, $c, $g, $t, $gap, $n, $length_dna);

  $a = $dna =~ tr/[aA]/A/;
  $c = $dna =~ tr/[cC]/C/;
  $g = $dna =~ tr/[gG]/G/;
  $t = $dna =~ tr/[tT]/T/;
  $gap = $dna =~ tr/\-/-/;

  # the Ns are whatever is not ACGT-
  $length_dna = $n = length $dna;
  $n -= $a;
  $n -= $c;
  $n -= $g;
  $n -= $t;
  $n -= $gap;

  return ($a, $c, $g, $t, $gap, $n, $length_dna);

}

##########################################
# read chromosome from file
#  my $chrom_seq = &read_chromosome($chromosome);

sub read_chromosome {
  my ($chromosome) = @_;

  #print "read chromosome $chromosome\n";

  $/ = "";
  open (SEQ, $chromosome) or $log->log_and_die("Can't open the dna file for $chromosome : $!\n");
  my $seq = <SEQ>;
  close SEQ;
  $/ = "\n";

  $seq =~ s/>CHROMOSOME_\w+//;
  $seq =~ s/\n//g;

  return $seq
}

##########################
# zip up files
###########################

sub zip_files {
  my @chromosomes = $quicktest ? qw(III):$wormbase->get_chromosome_names(-mito => 1);
  my $prefix= $wormbase->chromosome_prefix();

  foreach my $chr (@chromosomes){
    my $dna_file = "$dump_dir"."/$prefix".$chr.".dna";
    my $gff_file = "$dump_dir"."/$prefix".$chr.".gff";
    my $msk_file = "$dump_dir"."/$prefix".$chr."_masked.dna";

    if ($zipdna){
      if (-e $dna_file.".gz" ) {
	$log->write_to("\n ${dna_file}.gz exists\n");
      }
      elsif (-e $dna_file) {
	$log->write_to("\n Compressing $dna_file\n");
	system ("/bin/gzip -f $dna_file");
      }
      else {
	$log->write_to("\n ERROR: Couldn't find any dna chromosome files in $dump_dir\n");
      }
    }
    
    if ($zipgff){
      if (-e $gff_file.".gz" ) {
	$log->write_to(" ${gff_file}.gz exists\n");
      }
      elsif (-e $gff_file ) {
	$log->write_to(" Compressing $gff_file\n");
	system ("/bin/gzip -f $gff_file");
      }
      else {
	$log->write_to(" ERROR: Couldn't find any gff chromosome files in $dump_dir\n");
      }
    }	
    if (-e $msk_file.".gz" ) {
      $log->write_to(" ${msk_file}.gz exists\n");
    }
    elsif (-e $msk_file ) {
      $log->write_to(" Compressing $msk_file\n");
      system ("/bin/gzip -f $msk_file");
    }
    else {
      if ($chr ne "MtDNA") {	# it is OK for there not to be a repeat-masked file for the mitochondrion
	$log->write_to(" ERROR: Couldn't find any repeat-masked chromosomes in $dump_dir\n");
      }
    }
  }
}


#####################################################
# execute ace command: tace or giface
#####################################################

sub execute_ace_command {
  my ($command,$exec,$dir)=@_;
  open (WRITEDB,"| $exec $dir ") or do {
    $log->log_and_die("could not find $exec\n"); # throws only errors if it can't find the command
    die();
  };
  print WRITEDB $command;
  close (WRITEDB) or do {
	  $log->log_and_die("execute_ace_command failed\n"); # throws only errors if the command failed
	  die($!);
  }
}

######################################################


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

=head1 NAME - chromosome_dump.pl

=head2 USAGE

chromosome_dump.pl is a replacement script for the two existing
shell scripts: chrom_dump_3.0 and gff_dump.  This script can dump
chromosome-length DNA sequences for entire chromsomes in the autoace
database.  It can additionally generate chromosome GFF files, and
finally it can compress these files using gzip.

A log file is written to $basedir/logs/

All dumped files are written to $basedir/autoace/CHROMOSOMES/

chromosome_dump.pl arguments:

=over 4

=item -dna

Dump dna files from specified database (see -p flag), dumps one file for each of 
the six nuclear chromosomes, plus one file for the mitochondrial chromosome.

=back


=over 4

=item -gff

Dump gff files, dumps one file for each chromosome in the database.

=back


=over 4

=item -composition (optional)

Calculates composition statistics for any dna files that are generated.
Use in combination with -d option (see above).  Excludes mitochondrial 
chromosome.

=back

=item -database <database>

Specify database that you wish to dump dna/gff files from.  If -database is not specified
the script will dump from $basedir/autoace by default

=back


=over 4

=item -dump_dir <destination directory for dump files>

Specify destination of the dna and/or gff dump files generated from the -dna or -gff options.
If -dump_dir is not specified, dump files will be written to $basedir/autoace/CHROMOSOMES by default

=back


=over 4

=item -zipdna (optional)

Compresses any dna files using gzip (will remove any existing files first).  The -composition
option will be run before this stage if -composition is specified.

=back

=over 4

=item -zipgff (optional) 

Compresses any gff files using gzip (will remove any existing files first).      

=back

=over 4

=item -help

Show these help files.

=back


=over 4

=item -debug <user>

Only email log file to specified user

=back


=over 4

=item -test

Run in test mode and use test environment in ~wormpub/TEST_BUILD

=back


=over 4

=item -quicktest

Same as -test but only runs analysis for one chromosome (III)

=back


=over 4

=over 4

=head1 AUTHOR - Keith Bradnam

Email krb@sanger.ac.uk

=cut
