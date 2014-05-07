#!/software/bin/perl -w
#
# batch_pname_update.pl
# 
# This script has been written to automatically change the Public_name
# of all NameServerIDs specified in a text file.
#
# Last edited by: $Author: mh6 $
# Last edited on: $Date: 2014-05-07 08:35:36 $
#

use lib $ENV{'CVS_DIR'};
use lib '/nfs/WWWdev/SANGER_docs/lib/Projects/C_elegans';
use lib '/software/worm/lib/perl';
use NameDB_handler;
use Wormbase;
use Storable;
use Getopt::Long;

=pod

=head batch_pname_update.pl

=item Options:

  -file      file containing IDs and old/new names  <Mandatory>

    FORMAT:
    WBVar00278423 ot582 Blah
    WBGene00012345 AH6.4 Blah
  
  -domain    set domain to whatever (Gene Variation Feature)<Mandatory>
  -debug     limits to specified user <Optional>
  -species   can be used to specify non elegans
  -test      use the test nameserver  <Optional 4 testing>
  -user      username                 <Mandatory>
  -pass  password                 <Mandatory>

e.g. perl pname_update.pl -user blah -pass blah -species elegans -test -file variation_name_data

=cut




#connect to name server and set domain to $DOMAIN
my $PASS;
my $USER;
my $DOMAIN;
my ($debug, $test, $store, $species, $file);

GetOptions (
	    "file=s"     => \$file,
	    "debug=s"    => \$debug,
	    "test"       => \$test,
	    "store:s"    => \$store,
	    "species:s"  => \$species,
	    "domain=s"   => \$DOMAIN,
	    "user:s"	 => \$USER,
	    "pass:s"	 => \$PASS,
	   );


my $wormbase;

if ( $store ) {
  $wormbase = retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug   => $debug,
                             -test    => $test,
                             -organism => $species
			     );
}
# establish log file.
my $log = Log_files->make_build_log($wormbase);

# establish species
unless (defined$species){
  $species = "elegans";
$log->write_to ("Species has been set to elegans as it was not specified on command line\n\n");
}

#ENFORCE command line options
die "-domain option is mandatory\n" unless $DOMAIN;
die "-user option is mandatory\n" unless $USER;
die "-pass option is mandatory\n" unless $PASS;
die "-file option is mandatory\n" unless $file;

my $DB = $wormbase->test ? 'test_wbgene_id;mcs11:3307' : 'wbgene_id;shap:3303';
my $db = NameDB_handler->new($DB,$USER,$PASS,'/nfs/WWWdev/SANGER_docs/data');
$db->setDomain($DOMAIN);

open (DATA, "<$file");

while (<DATA>) {
  chomp;
  if ($_ =~/(WB\S+\d{8})\s+(\S+)\s+(\S+)/)	{
    $log->write_to ("\nProcessing $_\n");
    if (&check_name_exists($2)) {
      &addname($1,$3)
    }
    else {
      $log->write_to ("ERROR: ID $1 has a different Public name to that supplied $2\n");
    }
  }
  else {
    $log->write_to ("\nERROR: $_ has a line format error\n");
  } 
  next;
}

close DATA;
$log->mail;

sub check_name_exists {
  my $name = shift;
  my $ID = $db->idGetByTypedName('Public_name'=>$name)->[0];
  unless($ID) {  
    $log->write_to ("ERROR: $name does not exist in the nameserver\n");
    return undef;
  }
  else {
    $log->write_to ("Match: $name exists as the Public_name for $ID\n");
    return 1;
  }
}

sub addname {
  my $ID = shift;
  my $NEW = shift;
  $db->addName($ID,'Public_name'=>$NEW);
  $log->write_to ("$NEW added to $ID\n");
}
