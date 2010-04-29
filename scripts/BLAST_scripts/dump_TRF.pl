#!/usr/local/ensembl/bin/perl -w

use DBI;
use strict;
use lib $ENV{'CVS_DIR'};
use Getopt::Long;
use Wormbase;
use POSIX qw(ceil floor);
use Log_files;

#######################################
# command-line options                #
#######################################
my ($test, $debug, $help, $store);

GetOptions ("debug:s" => \$debug,
	    "test"    => \$test,
	    "help"    => \$help,
	    "store:s" => \$store,
	   );

my $wormbase;
if ( $store ) {
  $wormbase = retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( 'debug'   => $debug,
			     'test'    => $test,
			   );
}

# establish log file.
my $log = Log_files->make_build_log($wormbase);


my $dump_dir = "/lustre/scratch101/ensembl/wormpipe/dumps";
$dump_dir = glob("~wormpub/TEST_BUILD/") if $test;
my $acedb_database;
my $output = "$dump_dir/TRF.ace";
die &help if $help;

$output .= "_test" if $test;

open (OUT,">$output") or $log->log_and_die("cant open $output\n");


# retrieve hash of acc2clone
my %acc2clone;
$wormbase->FetchData("accession2clone",\%acc2clone);

my %clonesize;
$wormbase->FetchData("clonesize", \%clonesize);

# mysql database parameters
my $dbhost = "ia64b";
my $dbuser = "wormro";
my $dbname = "worm_dna";
$dbname .= "_test" if $test;

my $dbpass = "";
$log->write_to("dumping TRF from $dbname to $output\n");

my $wormrepeats_DB = DBI -> connect("DBI:mysql:$dbname:$dbhost", $dbuser, $dbpass, {RaiseError => 1})
  or $log->log_and_die("cannot connect to db, $DBI::errstr");


#retrieves descriptive information about the repeats from the database
my %repeat_info;
&GetRepeatInfo;


# build hash of internal_id to clone via EMBL accession
my $sth_f = $wormrepeats_DB->prepare ( q{SELECT
					 clone_id , name
					 FROM clone
	  	  	     } );

my %int_id2clone;

$sth_f->execute;
my $ref_results = $sth_f->fetchall_arrayref;

foreach my $pair (@$ref_results) {
  my $int_id = $$pair[0];
  my $acc = $$pair[1];
  my $clone = $acc2clone{$acc};

  if ($clone) {
    $int_id2clone{$int_id} = $clone;
  } else {
    print "no clone found for acc $acc : internal_id $int_id\n";
  }
}

# now retrieve the data from wormrepeats database
$sth_f = $wormrepeats_DB->prepare ( q{SELECT
				      contig_id, contig_start, contig_end,
				      score, contig_strand,
				      repeat_start,repeat_end,repeat_consensus_id
				      FROM repeat_feature
				      WHERE analysis_id = 11
				      ORDER BY contig_id
				     }
				  );

$sth_f->execute;
$ref_results = $sth_f->fetchall_arrayref;
my ($contig, $seq_start, $seq_end, $score, $strand, $hstart, $hend, $hid);
my $current_clone = "";
my $clone;
foreach my $repeat (@$ref_results) {
  ($contig, $seq_start, $seq_end, $score, $strand, $hstart, $hend, $hid) = @$repeat;
  
  if ($int_id2clone{$contig}) {
    $clone = $int_id2clone{$contig};
    if ( "$clone" ne "$current_clone" ) {
      $current_clone = $clone;
      print OUT "\nSequence : \"$clone\"\n";
      print OUT "Feature_data $clone:TRF 1 $clonesize{$clone}\n\n";
      print OUT "Feature_data : $clone:TRF\n";      
    }
    my $copy_no = ceil(abs($seq_start - $seq_end) / length( $repeat_info{$hid}->{'seq'} ));
    print OUT "Feature tandem $seq_start $seq_end $score \"$copy_no copies of ",length( $repeat_info{$hid}->{'seq'} ),"mer\"\n";
  } else {
    undef $clone;
  }
}

close OUT;

$log->mail;
exit(0);  

sub GetRepeatInfo
  {
    my $info = $wormrepeats_DB->prepare ( q{ SELECT * from repeat_consensus} );
    $info->execute;

    my $info_data = $info->fetchall_arrayref;
    foreach my $repeat ( @$info_data ) {
      $repeat_info{$$repeat[0]}->{'name'} = $$repeat[1];
      $repeat_info{$$repeat[0]}->{'class'} = $$repeat[2];
      $repeat_info{$$repeat[0]}->{'seq'} = $$repeat[3];
    } 
  }


sub help
  {
    print "===============================================\n$0\n
Extract TRF  data from worm_dna on ia64b\n\n
Writes ace file $output\n
\t\t-test appends _test to output filename.

Must be able to access Wormbase.pm\
Takes about 2 mins to dump whole genome\n\n
================================================\n\n";
  }

