#!/software/bin/perl -w

# Last updated by: $Author: mh6 $
# Last updated on: $Date: 2013-08-06 14:10:43 $

use strict;
use Net::FTP;
use lib $ENV{'CVS_DIR'};
use Wormbase;
use Getopt::Long;
use Log_files;
use Storable;
use DBI;
use Bio::SeqIO;

##############################
# command-line options       #
##############################

my ($help, $debug, $test, $verbose, $store, $wormbase);
my $species = 'elegans';
my $port= 3306;
my $server='farmdb1';
my $tmpDir='/tmp';
my ($user, $pass, $update);

GetOptions ('help'       => \$help,
            'debug=s'    => \$debug,
            'test'       => \$test,
	    'verbose'    => \$verbose,
	    'store:s'    => \$store,
	    'species:s'  => \$species,
	    'user:s'     => \$user,
	    'pass:s'     => \$pass,
	    'update'     => \$update,
            'port=s'     => \$port,
            'server=s'   => \$server,
            'tmpdir=s'   => \$tmpDir
           );

if ( $store ) {
  $wormbase = retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug   => $debug,
                             -test    => $test,
                             -organism=> $species
			     );
}

# in test mode?
if ($test) {
  print "In test mode\n" if ($verbose);

}

# establish log file.
my $log = Log_files->make_build_log($wormbase);
$log->write_to("Getting PFAM active sites for $species\n");


$log->write_to("\tconnecting to worm_pfam:$server as $user\n");
my $DB = DBI -> connect("DBI:mysql:worm_pfam:$server;port=$port", $user, $pass, {RaiseError => 1})
    or  $log->log_and_die("cannot connect to db, $DBI::errstr");

&update_database if $update;

my $sth_f = $DB->prepare ( 	q{	
	SELECT pfamseq.pfamseq_id, pfamseq.sequence, pfamseq_markup.residue, markup_key.label, pfamseq_markup.annotation 
	FROM pfamseq,pfamseq_markup, markup_key 
	WHERE pfamseq.ncbi_taxid = ?
	AND pfamseq.auto_pfamseq = pfamseq_markup.auto_pfamseq 
	AND pfamseq_markup.auto_markup = markup_key.auto_markup;
	  	  } );

$log->write_to("\tExcuting query . .\n");
$sth_f->execute($wormbase->ncbi_tax_id);
my $ref_results = $sth_f->fetchall_arrayref;

my %aa2pepid = $wormbase->FetchData('aa2pepid');
#&makepepseq_hash unless (%aa2pepid);

$log->write_to("\twriting output\n");
open (ACE,">".$wormbase->acefiles."/PFAM_active_sites.ace") or $log->log_and_die("cant open ".$wormbase->acefiles."/PFAM_active_sites.ace :$!");
foreach (@$ref_results) {
	my ($seq_id, $seq, $residue, $method, $annotation) = @$_;
	($method) = $method =~ /^(\S+)/;
	if($method eq "Active") {
		if($annotation and ($annotation !~ /NULL/)) {
			$method = $annotation;
		}else {
			$method = 'Active_site';
		}
	}
	if( $aa2pepid{$seq} ){
		my $pepid = $wormbase->wormpep_prefix.":".$wormbase->pep_prefix.&pad($aa2pepid{$seq});
		
		print ACE "\nProtein : \"$pepid\"\n";
		$log->write_to("can't find method for $seq_id, $seq, $residue, $method, $annotation \n") unless $method;
		print ACE "Motif_homol Active_site \"$method\" 0 $residue $residue 1 1\n"; 
	}
	else {
		$log->write_to("$seq_id sequence not in current set\n");
	}
}

$wormbase->load_to_database($wormbase->orgdb, $wormbase->acefiles."/PFAM_active_sites.ace", 'PFAM_active_sites', $log);
$log->mail();
exit;



sub update_database {
	$log->write_to("\n\nUpdating database from PFAM ftp site\n");
	
        my $ftp = Net::FTP->new('ftp.sanger.ac.uk',Debug => 0)
                  ||$log->log_and_die("Cannot connect to some.host.name: $@\n");
        $ftp->login("anonymous",'-anonymous@')
                  ||$log->log_and_die("Cannot login ${\$ftp->message}\n");
	$ftp->cwd ('pub/databases/Pfam/current_release/database_files/')
                  ||$log->log_and_die("Cannot change working directory ${\$ftp->message}\n");
        $ftp->binary()||$log->log_and_die("cannot change mode to binary ${\$ftp->message}\n");

	my @tables = qw(pfamseq ncbi_taxonomy markup_key pfamseq_markup);
	foreach my $table (@tables){
		$log->write_to("\tfetching $table.txt\n");
		
		
		# pfamseq table is subject to unannounced column re-ordering, so update the schema.
		if ($ftp->get("${table}.sql.gz","$tmpDir/${table}.sql.gz")){
		    $log->write_to("\tupdating the $table table schema\n");
                    $wormbase->run_command("echo \"SET FOREIGN_KEY_CHECKS=0;\"> $tmpDir/${table}.sql",$log);
		    $wormbase->run_command("zcat $tmpDir/$table.sql.gz >> $tmpDir/${table}.sql", $log);
                    $wormbase->run_command("echo \"SET FOREIGN_KEY_CHECKS=1;\">> $tmpDir/${table}.sql",$log);
		    $wormbase->run_command("mysql -h $server -P$port -u$user -p$pass worm_pfam < $tmpDir/${table}.sql", $log);
		    $wormbase->run_command("rm -f $tmpDir/${table}.sql.gz", $log);
		    $wormbase->run_command("rm -f $tmpDir/${table}.sql", $log);
		} else {$log->write_to("\tcouldn't update the $table table schema\n");}

		if ($ftp->get("${table}.txt.gz","$tmpDir/${table}.txt.gz")){
		  $log->write_to("\tunzippping $tmpDir/$table.txt\n");
		  $wormbase->run_command("gunzip -f $tmpDir/$table.txt.gz", $log);
		} elsif ($ftp->get("${table}.txt","$tmpDir/${table}.txt")){
		  $log->write_to("\tgzip archive abscent....using $table.txt.\n");
		} else {
		  $log->log_and_die("Couldn't find $table file to download :(\n");
		}


		# flush the table
		$log->write_to("\tclearing table $table\n");
		$DB->do("TRUNCATE TABLE $table") or $log->log_and_die($DB->errstr."\n");
		# load in the new data.
		$log->write_to("\tloading data in to $table\n");
                $DB->do("SET FOREIGN_KEY_CHECKS=0");		
		$DB->do("LOAD DATA LOCAL INFILE \"$tmpDir/$table.txt\" INTO TABLE $table".' FIELDS ENCLOSED BY \'\\\'\'') or $log->log_and_die($DB->errstr."\n");
                $DB->do("SET FOREIGN_KEY_CHECKS=1");

		# this will fall to pieces as soon as Rob changes the name of the column again
		if ($table eq 'pfamseq') {
                  $log->write_to("\tcleaning quotation marks from $table\n");
		  $DB->do("UPDATE pfamseq SET description=REPLACE(description,'\\'','')");
                  $DB->do("UPDATE pfamseq SET description=REPLACE(description,'\"','')");
	        }
		# clean up files
		
		$wormbase->run_command("rm -f $tmpDir/$table.txt", $log);

	      }
	$log->write_to("Database update complete\n\n");
}


sub makepepseq_hash {
	$log->write_to("Updating seq->id hash\n");
	my %cds2pepid = $wormbase->FetchData('cds2pepid');
	my $pepfile = $wormbase->wormpep."/".$wormbase->pepdir_prefix."pep".$wormbase->get_wormbase_version;
	my $seqs = Bio::SeqIO->new('-file' => $pepfile, '-format' => 'fasta');
	while(my $pep = $seqs->next_seq){ 
		$aa2pepid{$pep->seq}=$wormbase->pep_prefix.$cds2pepid{$pep->id};
	}

	#data dump for future
	open (PEP,">".$wormbase->common_data."/pepseq2pepid.dat") or $log->log_and_die("cant Data::Dump ".$wormbase->common_data."/pepseq2pepid.dat :$!\n");
	print PEP Data::Dumper->Dump([\%aa2pepid]);
	close PEP;
}

sub pad {
	my $num = shift;
	return sprintf "%05d" , $num;
}
