#!/usr/local/ensembl/bin/perl -w
#
# Originally written by Marc Sohrmann (ms2@sanger.ac.uk)
#
# Dumps protein motifs from ensembl mysql (protein) database to an ace file
#
# Last updated by: $Author: mh6 $
# Last updated on: $Date: 2008-03-11 15:20:59 $

use lib $ENV{'CVS_DIR'};

use strict;
use DBI;
use Getopt::Long;
use Wormbase;
use Storable;
use Log_files;

my ($WPver, @methods);
my ($store, $test, $debug,$dump_dir,$dbname);

GetOptions(
	   "database:s" => \$dbname,
	   "methods=s"   => \@methods,
	   "store:s"   => \$store,
	   "test"      => \$test,
	   "debug:s"   => \$debug,
	   "dumpdir=s" => \$dump_dir,
	   "dbname=s"  => \$dbname,
	  );

my $wormbase;
if ( $store ) {
  $wormbase = retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug   => $debug,
                             -test    => $test,
			     );
}

my $log = Log_files->make_build_log($wormbase);
$dump_dir ||= '/lustre/work1/ensembl/wormpipe/dumps';

# define the names of the methods to be dumped
@methods = qw(Ncoils Seg Signalp Tmhmm Pfam) unless @methods;

$log->write_to("Dumping methods".@methods."\n");

# mysql database parameters
my $dbhost = "ia64d";
my $dbuser = "wormro";
$dbname ||= "worm_ensembl_elegans";
print "Dumping motifs from $dbname\n";
my $dbpass = "";

# to get the current time...
sub now {
    return sprintf ("%04d-%02d-%02d %02d:%02d:%02d",
                     sub {($_[5]+1900, $_[4]+1, $_[3], $_[2], $_[1], $_[0])}->(localtime));
}

# create output files
open(ACE,">$dump_dir/".$dbname."_motif_info.ace") || die "cannot create ace file:$!\n";
open(LOG,">$dump_dir/".$dbname."_motif_info.log") || die "cannot create log file:$!\n";

# make the LOG filehandle line-buffered
my $old_fh = select(LOG);
$| = 1;
select($old_fh);

$old_fh = select(ACE);
$| = 1;
select($old_fh);


$log->write_to("DUMPing protein motif data from ".$dbname." to ace\n---------------------------------------------------------------\n\n");

# connect to the mysql database
print LOG "connect to the mysql database $dbname on $dbhost as $dbuser [".&now."]\n\n";
my $dbh = DBI -> connect("DBI:mysql:$dbname:$dbhost", $dbuser, $dbpass, {RaiseError => 1})
    || $log->log_and_die("cannot connect to db, $DBI::errstr\n");

# get the mapping of method 2 analysis id
my %method2analysis;
print LOG "get mapping of method to analysis id [".&now."]:\n";
my $sth = $dbh->prepare ( q{ SELECT analysis_id
                               FROM analysis
                              WHERE logic_name = ?
                           } );

foreach my $meth (@methods) {
    $sth->execute ($meth);
    (my $anal) = $sth->fetchrow_array;
    $method2analysis{$meth} = $anal;
    $log->write_to("method: $meth => analyis_id: $anal\n");
}

# prepare the sql querie
my $sth_f = $dbh->prepare ( q{ SELECT stable_id, seq_start, seq_end, hit_id, hit_start, hit_end, score
                                 FROM protein_feature,translation_stable_id
                                WHERE analysis_id = ? AND translation_stable_id.translation_id = protein_feature.translation_id
                             } );

# get the motifs
my %motifs;
my %pfams;
my %cds2wormpep;
$wormbase->FetchData('cds2wormpep',\%cds2wormpep);

foreach my $meth (@methods) {
  $log->write_to("processing $meth\n");
  $sth_f->execute ($method2analysis{$meth});
  my $ref = $sth_f->fetchall_arrayref;
  foreach my $aref (@$ref) {
    my ($_prot, $start, $end, $hid, $hstart, $hend, $score) = @$aref;
    my $prot=($cds2wormpep{$_prot}||$_prot);
    my $line;
    if ($meth eq "Pfam") {
      if( $hid =~ /(\w+)\.\d+/ ) {
	$hid = $1;
      }
       $line = "Motif_homol \"PFAM:$hid\" \"pfam\" $score $start $end $hstart $hend";
      push (@{$motifs{$prot}} , $line);
    }
    else {
      $line = "Feature \"$meth\" $start $end $score";
      push (@{$motifs{$prot}} , $line);
    }
  }
}

# print ace file
my $prefix = "WP";
if( $dbname =~ /brig/) {
  $prefix = "BP";
}elsif($dbname =~/rem/){
	$prefix='RP';
}

foreach my $prot (sort {$a cmp $b} keys %motifs) {
    print ACE "\n";
    # cds2wormpep conversion
    print ACE "Protein : \"$prefix:$prot\"\n";
    foreach my $line (@{$motifs{$prot}}) {
        print ACE "$line\n";
    }
}

    
$sth->finish;
$sth_f->finish;
$dbh->disconnect;

close ACE;

$log->write_to("\nEnd of Motif dump\n");

$log->mail;
exit(0);
