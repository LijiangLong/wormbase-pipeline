#!/usr/local/bin/perl -w
#
# Originally written by Gary Williams (gw3@sanger), modifying a script by Marc Sohrmann (ms2@sanger.ac.uk)
#
# Dumps InterPro protein motifs from ensembl mysql (protein) database to an ace file
#
# Last updated by: $Author: gw3 $
# Last updated on: $Date: 2007-10-12 12:20:47 $


use strict;
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Carp;
use IO::Handle;
use Getopt::Long;
use Cwd;
use Storable;
use DBI;

my $WPver; 
my $database; 
my $mysql; 
my $method; 
my $verbose; 
my $help;
my ($store, $test, $debug);



GetOptions("debug:s"    => \$debug,
	   "database:s" => \$database,
	   "mysql"      => \$mysql,
	   "method=s"   => \$method,
	   "verbose"    => \$verbose,
	   "test"       => \$test,
	   "help"       => \$help,
	   "store:s"    => \$store,
	  );

# Display help if required
&usage("Help") if ($help);

my $wormbase;
if ( $store ) {
  $wormbase = retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug   => $debug,
                             -test    => $test,
			     );
}

my $log = Log_files->make_build_log($wormbase);

if ($test) {
  $database = "worm_peptest";
}


##########################
# MAIN BODY OF SCRIPT
##########################

# set up InterPro ID mapping
my %ip_ids = get_ip_mappings();                # hash of Databases hash of IDs
 


# define the names of the Interpro methods to be dumped
my @methods;
if ($method ) {
  push(@methods,$method)
}else{

# add new methods (logic_names, as defined in the mysql database 'analysis' table, column 'logic_name') 
# as they are added to the pipeline
#
#  @methods= qw(hmmpfam prints profile pirsf hmmtigr hmmsmart );
#  @methods= qw(hmmpfam pirsf hmmtigr hmmsmart prosite profile);
  @methods= qw(prosite prints profile blastprodom hmmsmart hmmpanther hmmpfam hmmtigr pirsf superfamily gene3d);
}


# define the Database names that InterPro uses in interpro.xml
# and the logic names (as specified in @methods) that search those databases
my %method_database = (
		       'prosite'     => 'PROSITE',
		       'prints'      => 'PRINTS',
		       'profile'     => 'PROFILE',
		       'blastprodom' => 'PRODOM',
		       'hmmsmart'    => 'SMART',
		       'hmmpanther'  => 'PANTHER',
		       'hmmpfam'     => 'PFAM',
		       'hmmtigr'     => 'TIGRFAMs',
		       'coils'       => 'COIL',
		       'seg'         => 'SEG',
		       'tmhmm'       => 'TMHMM',
		       'signalp'     => 'SIGNALP',
		       'pirsf'       => 'PIRSF',
		       'superfamily' => 'SUPERFAMILY',
		       'gene3d'      => 'GENE3D',
	       );

# mysql database parameters
my $dbhost = "ia64b";
my $dbuser = "wormro";		# worm read-only access
my $dbname = "worm_pep";
$dbname = $database if $database;
print "Dumping motifs from $dbname\n";
my $dbpass = "";

# to get the current time...
sub now {
    return sprintf ("%04d-%02d-%02d %02d:%02d:%02d",
                     sub {($_[5]+1900, $_[4]+1, $_[3], $_[2], $_[1], $_[0])}->(localtime));
}

# create output files
my $dump_dir = $wormbase->farm_dump;
if ($test) {
  $dump_dir = ".";
}
open(ACE,">$dump_dir/".$dbname."_interpro_motif_info.ace") || $log->log_and_die("cannot create ace file:$!\n");

# make the ACE filehandle line-buffered
my $old_fh = select(ACE);
$| = 1;
select($old_fh);


$log->write_to("DUMPing protein motif data from ".$dbname." to ace\n");
print "DUMPing protein motif data from ".$dbname." to ace\n" if ($verbose);
$log->write_to("----------------------------------------------------\n\n");
print "----------------------------------------------------\n\n" if ($verbose);

# connect to the mysql database
$log->write_to("connect to the mysql database $dbname on $dbhost as $dbuser\n\n");
print "connect to the mysql database $dbname on $dbhost as $dbuser\n\n" if ($verbose);
my $dbh = DBI -> connect("DBI:mysql:$dbname:$dbhost", $dbuser, $dbpass, {RaiseError => 1})
    || $log->log_and_die("cannot connect to db, $DBI::errstr");

# get the mapping of method 2 analysis id
my %method2analysis;
$log->write_to("get mapping of method to analysis id \n");
print "get mapping of method to analysis id \n" if ($verbose);
my $sth = $dbh->prepare ( q{ SELECT analysis_id
                               FROM analysis
                              WHERE logic_name = ?
                           } );

foreach my $method (@methods) {
    $sth->execute ($method);
    (my $anal) = $sth->fetchrow_array;
    $method2analysis{$method} = $anal;
#    $log->write_to("$method  $anal\n");
#    print "$method  $anal\n" if ($verbose);
}

# prepare the sql query
my $sth_f = $dbh->prepare ( q{ SELECT protein_id, seq_start, seq_end, hit_id, hit_start, hit_end, score, evalue
				   FROM protein_feature
				   WHERE evalue <= "0.1"
				   AND analysis_id = ?
                             } );

# counts extracted for each method
my %counts;

# get the motifs
my %motifs;
foreach my $method (@methods) {
  $log->write_to("processing $method\n");
  print "processing $method: $method2analysis{$method}\n" if ($verbose);
  $sth_f->execute ($method2analysis{$method});
  my $ref = $sth_f->fetchall_arrayref;
  $counts{$method} = scalar(@$ref);
  print "We found $counts{$method} results for $method\n";

  foreach my $aref (@$ref) {
    my ($prot, $start, $end, $hid, $hstart, $hend, $score, $evalue) = @$aref;
    if ($method eq "hmmpfam") {
      if( $hid =~ /(\w+)\.\d+/ ) {
	$hid = $1;
      }
    }
    # convert Database ID to InterPro ID (if it is in InterPro)
    my $database = $method_database{$method};
    if (exists $ip_ids{$database}{$hid}) {
      my $ip_id = $ip_ids{$database}{$hid};
      print "Convert IDs $method: $hid -> InterPro: $ip_id\n" if ($verbose);
      my @hit = ( $ip_id, $start, $end, $hstart, $hend, $score, $evalue );
      push @{$motifs{$prot}}, [ @hit ];
    } else {
      print "$database ID $hid is not in InterPro\n" if ($verbose);
    }
  }
}


# print ace file
my $prefix = "WP";
if ($dbname eq "worm_brigpep") {
  $prefix = "BP";
}

# here we need to do:
# foreach protein:
#   sort by interpro id and then start position
#   and merge any overlapping hits with the same id 
#    by taking the positions of the widest coverage
#    and the lowest of the e-values

my %merged = ();			# the resulting hash of lists of merged hits
my $merged_count=0;
my $motif_count = 0;
my $protein_count = 0;

foreach my $prot ( keys %motifs ) {

  $protein_count++;

  # sort the hits for this protein by ID and start position
  my @array = @{$motifs{$prot}};
  @array = sort { $a->[0] cmp $b->[0]  or  $a->[1] <=> $b->[1] } @array;
 
  # go through the hits for this protein looking for the same InterPro Id hits that overlap
  # then merge them
  my $prev_id = "";
  my $merged_start;
  my $merged_end;
  my $merged_hstart;
  my $merged_hend;
  my $merged_score;
  my $merged_evalue;
  my @merged_hit;
  foreach my $hit (@array) {

    my ( $ip_id, $start, $end, $hstart, $hend, $score, $evalue ) = @$hit;

    # is this a new ID or the same ID at a different part of the protein?
    #print "merged($prev_id)= $merged_start $merged_end : this($ip_id)= $start $end\n";
    if ($prev_id ne $ip_id || $start > $merged_end) {

      # save the merged hit
      if ($prev_id ne "") {
	@merged_hit = ( $prev_id, $merged_start, $merged_end, $merged_hstart, $merged_hend, $merged_score, $merged_evalue );
	push @{$merged{$prot}}, [ @merged_hit ];
	$motif_count++;
      }

      # reset the values for the merged hit to be the values of the new ID
      $prev_id = $ip_id;
      $merged_start = $start;
      $merged_end = $end;
      $merged_hstart = $hstart;
      $merged_hend = $hend;
      $merged_score = $score;
      $merged_evalue = $evalue; 

    } else {
      # merge this hit into the merged hits
      # some results (e.g. prints) have zero hstart and hend, so overwrite these
      if ($merged_start > $start) {$merged_start = $start;}
      if ($merged_end < $end) {$merged_end = $end;}
      if ($hstart != 0 && ($merged_hstart == 0 || $merged_hstart > $hstart)) {$merged_hstart = $hstart;}
      if ($merged_hend == 0 || $merged_hend < $hend) {$merged_hend = $hend;}
      if ($merged_score < $score) {$merged_score = $score;}
      if ($merged_evalue > $evalue) {$merged_evalue = $evalue;}
      #print "merged to $merged_start $merged_end";
      $merged_count++;
    }

  }
  # save the last merged ID
  @merged_hit = ( $prev_id, $merged_start, $merged_end, $merged_hstart, $merged_hend, $merged_score, $merged_evalue );
  push @{$merged{$prot}}, [ @merged_hit ];
  $motif_count++;

}

print "\nMerged $merged_count overlapping hits of the same InterPro ID\n" if ($verbose);
$log->write_to("\nMerged $merged_count overlapping hits of the same InterPro ID\n");

print "\nHave $motif_count InterPro domains in $protein_count proteins\n" if ($verbose);
$log->write_to("\nHave $motif_count InterPro domains in $protein_count proteins\n");

my %domain_counts = ();
# now print out the ACE file
foreach my $prot (sort {$a cmp $b} keys %merged) {
    print ACE "\n";
    print ACE "Protein : \"$prefix:$prot\"\n";

    # count the number of domains in this protein for the statistics
    my $domains = scalar(@{$merged{$prot}});
    $domain_counts{$domains}++;
    if ($verbose && $domains > 100) {
      print  "$prot has $domains InterPro domains!\n";
    }

    foreach my $hit (@{$merged{$prot}}) {
      my ($ip_id, $start, $end, $hstart, $hend, $score, $evalue) = @$hit;
      my $line = "Motif_homol \"INTERPRO:$ip_id\" \"interpro\" $evalue $start $end $hstart $hend";
      print "$line\n" if ($verbose);
      print ACE "$line\n";
    }
}

    
$sth->finish;
$sth_f->finish;
$dbh->disconnect;

close ACE;

####################################
# print some statistics to the log #
####################################

print "\nTable of InterPro domains found per protein\n" if ($verbose);
$log->write_to("\nTable of InterPro domains found per protein\n");
print "No. domains\tNo. of Proteins\n" if ($verbose);
$log->write_to("No. domains\tNo. of Proteins\n");
print "-----------\t---------------\n" if ($verbose);
$log->write_to("-----------\t---------------\n");
foreach my $domains (sort {$a <=> $b} keys %domain_counts) {
  print "$domains\t\t$domain_counts{$domains}\n" if ($verbose);
  $log->write_to("$domains\t\t$domain_counts{$domains}\n");
}


foreach my $method (keys %counts) {
  if ($counts{$method} == 0) {
    print "ERROR: ";
  }
  print "$method: found $counts{$method} hits\n";
  if ($counts{$method} == 0) {
    $log->write_to("ERROR: ");
    $log->error;
  }
  $log->write_to("$method: found $counts{$method} hits\n");
}

$log->mail;
exit(0);

##############################################################
#
# Subroutines
#
##############################################################
 
###############################
# Prints help and disappears  #
###############################
 
sub usage {
  my $error = shift;
 
  if ($error eq "Help") {
    # Normal help menu
    system ('perldoc',$0);
    exit (0);
  }
}

#########################
# get the interpro file #
#########################

sub get_interpro {

  my $latest_version = $_[0];
 
  my $get_latest = 1;		# set to 0 to skip this FTP during debugging
  if( $get_latest == 1)
  {				# 
				#Get the latest version
    print "Attempting to FTP the latest version of interpro.xml from ebi \n" if ($verbose);
    `wget -O $latest_version.gz ftp://ftp.ebi.ac.uk/pub/databases/interpro/interpro.xml.gz`;
    `gunzip "${latest_version}.gz"`;
  }
  else {
    print "Using the existing version of interpro2go mapping file (ie not FTPing latest)\n" if ($verbose);
  }
}

#########################################################
# reads in data for database ID to InterPro ID mapping  #
#########################################################


sub get_ip_mappings {

  my $ip_ids = ();       # hash of Databases hash of IDs
 
  # the interpro.xml file can be obtained from:
  # ftp.ebi.ac.uk/pub/databases/interpro/interpro.xml.gz

  # store it here
  my $dir = "/lustre/scratch1/ensembl/wormpipe";
  my $file = "$dir/interpro.xml";

  # get the interpro file from the EBI
  unlink $file;
  get_interpro($file);

 
  open (XML, "< $file") || die "Failed to open file $file\n";
 
  my $in_member_list = 0;       # flag for in data ID section of XML file
  my $IPid;
  my $IPname;
  my $this_db;
  my $this_dbkey;
 
  while (my $line = <XML>) {
 
    if ($line =~ /<interpro id=\"(\S+)\"/) {
      $IPid = $1;
    } elsif ($line =~ /<member_list>/) { # start of database ID section
      $in_member_list = 1;
    } elsif ($line =~ m|</member_list>|) { # end of database ID section
      $in_member_list = 0;
    } elsif ($in_member_list && $line =~ /<db_xref/) {
      ($this_db, $this_dbkey) = ($line =~ /db=\"(\S+)\" dbkey=\"(\S+)\" /);
      #print "$IPid $this_db $this_dbkey\n";
      $ip_ids{$this_db}{$this_dbkey} = $IPid;
    }
  }
  close (XML);
  unlink $file;

  return %ip_ids;
}

######################################## 
# Add perl documentation in POD format #
######################################## 

# This should expand on your brief description above and add details
# of any options that can be used with the program.
#
# Such documentation can be viewed using the perldoc command.
 
 
__END__
 
=pod
 
=head2 NAME - dump_interpro_motif.pl
 
=head1 USAGE
 
=over 4

 
=item script_template.pl [-options] 

=back 

This script reads the
results of Pfam, PRINTS, SMART, TIGR, PIRSF and Profile domain hits
from the mysql database, converts the IDs from these hits into
InterPro IDs and then merges overlapping hits which have the same
InterPro ID into single InterPro hits.

It then writes out an .ace file of the resulting InterPro hits.

script_template.pl MANDATORY arguments:
 
=over 4
 
=item none
 
=back
 
script_template.pl  OPTIONAL arguments:
 
=over 4
 
=item -help, Help
 
=back

=over 4

=item -database=database, Specify a specific database for debugging

=back

=over 4

=item -mysql=servername, Specify a specific mysql server for debugging.

=back

=over 4

=item -method=method, Specify a specific result method for debugging.

=back

=over 4

=item -test, use the test database 'worm_peptest'.

=back

=over 4

=item -debug=username, run in debug mode.

=back

=over 4

=item -verbose,  Verbose output

=back


=head1 REQUIREMENTS
 
=over 4
 
=item This script must be run where it can see /lustre/scratch1/ensembl/wormpipe/ as it puts the temporary interpro.xml file in there.
 
=back
 
=head1 AUTHOR
 
=over 4
 
=item Gary Williams (gw3@sanger.ac.uk)
 
=back
 
=cut
