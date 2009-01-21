#!/software/bin/perl -w

use lib $ENV{'CVS_DIR'};
use strict;
use Getopt::Long;
use Wormbase;
use Log_files;
use LSF RaiseError => 0, PrintError => 1, PrintOutput => 0;
use LSF::JobManager;

my $debug;
my ($prepare, $run, $final);
my $chromosome;

GetOptions (
	    'prepare' => \$prepare,
	    'run'     => \$run,
	    'final'   => \$final,
	    'debug:s' => \$debug,
	    'chromosome:s' => \$chromosome,
	    'chromosomes:s' => \$chromosome
	   );

my $log = Log_files->make_build_log($debug);

$log->log_and_die("Cant do those options ( -prepare and /or -run with -final )\n") if ( ($run or $prepare) and $final );

my $wormpub = glob("~wormpub");
my $datdir = "$wormpub/analysis/UTR";
my $GFFdir = "wormsrv2:/wormsrv2/autoace/GFF_SPLITS/GFF_SPLITS";

my @chromosomes = $chromosome ? split(/,/,join(',',$chromosome)) : qw( I II III IV V X MtDNA);

my $errors = 0;

if ( $prepare ) {
  $log->write_to("Copying GFF files from $GFFdir to $datdir \n");
  foreach my $chrom ( @chromosomes ) {

    # copy Coding_transcripts
    $errors++ if( system ("scp $GFFdir/CHROMOSOME_$chrom.Coding_transcript.gff $datdir/") );

    # copy Coding_exons
    $errors++ if( system ("scp $GFFdir/CHROMOSOME_$chrom.coding_exon.gff $datdir/") );

    # copy CDS
    $errors++ if( system ("scp $GFFdir/CHROMOSOME_$chrom.CDS.gff $datdir/") );
  }
}

$log->log_and_die("There were errors in the GFF copying so I stopping\n") unless ($errors == 0);

if( $run ) {
  $log->write_to("Submitting bsub jobs\n");
  my $lsf = LSF::JobManager->new();
  foreach my $chrom ( @chromosomes ) {
    my $err  = "$datdir/$chrom.err.$$";
    my $bsub =  $wormbase->build_cmd("make_UTR_GFF.pl $chrom");
    print "$bsub\n";
    $lsf->submit('-e' => $err, '-J'=> "UTR_$chrom", $bsub);
  }

  $lsf->wait_all_children('history' => 1);
  for my $job ($lsf->jobs){ # much quicker if history is pre-cached
      $log->error("job ".$job->id." failed\n") if ($job->history->exit_status != 0);
  }
}

if ( $final ) {

  my @err_files = glob("$datdir/*err*");
  foreach (@err_files ) {
    if( -s "$_" ) {
      $log->write_to("ERROR : $_ is NOT zero length");
    }
    else {
      unlink("$_");
    }
  }
  $log->write_to("Copying GFF files back to wormsrv2\n");
  foreach my $chrom ( @chromosomes ) {
    if( system ("scp $datdir/CHROMOSOME_$chrom.UTR.gff $GFFdir/") ) {
      $log->write_to("ERROR: copying $datdir/CHROMOSOME_$chrom.UTR.gff to $GFFdir\n");
    }
    else {
      unlink("$datdir/CHROMOSOME_$chrom.UTR.gff");
    }
  }
}


$log->mail;

exit(0);
