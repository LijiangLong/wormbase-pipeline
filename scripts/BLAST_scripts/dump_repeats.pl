#!/usr/local/ensembl/bin/perl -w

use DBI;
use strict;
use lib $ENV{'CVS_DIR'};
use Getopt::Long;
use Wormbase;
use Log_files;
use Storable;
use POSIX qw(ceil);

use lib '/software/worm/lib/bioperl-live';
use lib '/software/worm/ensembl/ensembl/modules';
use Bio::EnsEMBL::DBSQL::DBAdaptor;


#######################################
# command-line options                #
#######################################
my ($test, $debug, $help, $store,$database,$dumpdir);

GetOptions ("debug:s" => \$debug,
	    "test"    => \$test,
	    "help"    => \$help,
	    "store:s" => \$store,
	    'database:s' => \$database,
	    'dump_dir=s' => \$dumpdir,
           );

my $wormbase;
if ( $store ) {
  $wormbase = Storable::retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( 'debug'   => $debug,
                             'test'    => $test,
			     );
}

my $dbobj = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
                                                       '-host'   => 'ia64d',
                                                       '-user'   => 'wormro',
                                                       '-dbname' => $database
                                                      ) || die (@!);


# establish log file.
my $log = Log_files->make_build_log($wormbase);

my $dump_dir = ($dumpdir || $wormbase->acefiles);
my $output = "$dump_dir/repeat_homologies.ace";
die &help if $help;

$log->write_to("Dumping to $output\n");

open (OUT,">$output") or $log->log_and_die("cant open $output\n");


# retrieve hash of acc2clone
my %acc2clone;
$wormbase->FetchData("accession2clone",\%acc2clone) if (ref $wormbase eq 'Elegans');

my $seq_level = ref $wormbase eq 'Elegans'? 'clone' : 'toplevel';

my $sa=$dbobj->get_SliceAdaptor();
foreach my $seq ( @{$sa->fetch_all($seq_level)}){
	my $acc=$seq->seq_region_name;
	$acc=~s/\.\d+$//;
	my $clone=($acc2clone{$acc}||$acc);
        my $clonesize=$seq->seq_region_length;

	my $repeats = $seq->get_all_RepeatFeatures('RepeatMask');
        
	if (scalar @$repeats) {
         print OUT "\nSequence : \"$clone\"\n";
         print OUT "Homol_data $clone:RepeatMasker 1 $clonesize\n\n";
         print OUT "Homol_data : $clone:RepeatMasker\n";
        }

	foreach my $feature (@$repeats){
	     printf OUT ("Motif_homol %s RepeatMasker %s %s %s ",
	        $feature->display_id,$feature->score,$feature->seq_region_start,$feature->seq_region_end);
	     if ($feature->strand>0){
		     printf OUT ("%s %s\n",$feature->hstart,$feature->hend);
	     } else { 
		     printf OUT ("%s %s\n",$feature->hend,$feature->hstart);
	     }
	}

        $repeats = $seq->get_all_RepeatFeatures('TRF');
	if (scalar @$repeats) {
         print OUT "\nSequence : \"$clone\"\n";
         print OUT "Feature_data $clone:TRF 1 $clonesize\n\n";
         print OUT "Feature_data : $clone:TRF\n";
        }

	foreach my $feature (@$repeats){
            my $copy_no=ceil(abs($feature->seq_region_start - $feature->seq_region_end) / length( $feature->repeat_consensus->seq ));
	    printf OUT ("Feature tandem %s %s %s \"%i copies of %imer\"\n",
		    $feature->seq_region_start,$feature->seq_region_end,$feature->score,$copy_no,length($feature->repeat_consensus->seq )); 
	}

        $repeats = $seq->get_all_RepeatFeatures('Dust');
	if (scalar @$repeats) {
         print OUT "\nSequence : \"$clone\"\n";
         print OUT "Feature_data $clone:Dust 1 $clonesize\n\n";
         print OUT "Feature_data : $clone:Dust\n";
        }

	foreach my $feature (@$repeats){
	    printf OUT ("Feature dust %i %i %i \"low_complexity region\"\n",
		    $feature->seq_region_start,$feature->seq_region_end,length($feature->repeat_consensus->seq )); 
	}

}


close OUT;

$log->mail;
exit(0);
sub help {
    print "===============================================\n$0\n
Extract RepeatMasker and TRF data from worm_ensembl databases on ia64d\n\n
Writes ace file $output\n

Must be able to access Wormbase.pm and /software/worm/ensembl/\
Takes about 2 mins to dump whole genome\n\n
================================================\n\n";
}

