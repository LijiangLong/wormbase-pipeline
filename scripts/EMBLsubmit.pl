#!/usr/bin/env perl
#

# Last updated by: $Author: klh $                      
# Last updated on: $Date: 2011-12-21 11:30:42 $        

use strict;
use Getopt::Long;
use Net::FTP;
use Storable;

use lib $ENV{'CVS_DIR'};
use Wormbase;
use Log_files;

	   
###################################################
# command-line options                            #
###################################################

my $ftp_host = "ftp-private.ebi.ac.uk";
my $ftp_dir  = "/TXhExzF7KgVBMHtJXDct/to_ena";
my ($ftp_login, $ftp_user, $ftp_pass);

my ($help, $debug, $test, $verbose, $species, $comment, @clones);

GetOptions (
  "debug=s"      => \$debug,
  "test"         => \$test,
  "help"         => \$help,
  "species=s"    => \$species,
  "verbose"      => \$verbose,
  "ftphost=s"    => \$ftp_host,
  "ftplogin=s"   => \$ftp_login,
  "ftpdir=s"     => \$ftp_dir,
  "ftppass=s"    => \$ftp_pass,
  "clones=s@"    => \@clones,
  "comment=s"    => \$comment,
    );

my $wormbase = Wormbase->new(
  -test     => $test,
  -debug    => $debug,
  -organism => $species,
);

$species = $wormbase->species;

# establish log file.
my $log = Log_files->make_build_log($wormbase);

my ($current_date, $current_time) = &get_current_timestamp();
my $submit_repo = $wormbase->submit_repos;
my $ws_version = $wormbase->get_wormbase_version_name;
my $submit_log_prefix = sprintf("%s/submit_logs/submitted_to_ENA", $submit_repo);



if (defined $ftp_login) {
  ($ftp_user, $ftp_pass) = $ftp_login =~ /^(\S+):(\S+)$/;
  if (not defined $ftp_pass) {
    $log->log_and_die("Invalid login details specified with -ftplogin - should be username:password\n");
  }
} else {
  my $login_details_file = $wormbase->wormpub . "/ebi_resources/EBIFTP.s";
  open(my $infh, $login_details_file)
      or $log->log_and_die("Can't open secure account details file $login_details_file\n");
  while (<$infh>){
    /^USER_ID:(\S+)$/ and $ftp_user = $1;
    /^PASSWD:(\S+)$/ and $ftp_pass = $1;
  }
  close($infh);

  $log->log_and_die("Could not find both user name and password in login details file\n")
      if not defined $ftp_user or not defined $ftp_pass;
  
}

###################################################
# Establish ftp connection                        #
###################################################
my $ftp = Net::FTP->new($ftp_host, Debug => 0) 
    or $log->log_and_die("Cannot connect to $ftp_host: $@");
$ftp->login($ftp_user,"$ftp_pass\@")
    or $log->log_and_die ("Cannot login to $ftp_host using WormBase credentials\n". $ftp->message);
$ftp->cwd($ftp_dir) 
    or $log->log_and_die ("Cannot change into to_ena dir for upload of files\n". $ftp->message);

###################################################
# get list of entries to be submitted
###################################################
my (@changed_embl, @changed_seq);

if (@clones) {
  $log->write_to("User specified clones to submit on the command line - not looking to submit_repo for changes\n");
  @changed_embl = @clones;
} else {
  open(my $cmdfh, "cd $submit_repo && git ls-files -m |")
      or $log->log_and_die("Failed to execute git command to get list of embl files to submit\n");
  while(<$cmdfh>) {
    /^(\S+\.embl)$/ and push @changed_embl, $1;
    /^(\S+\.fasta)$/ and push @changed_seq, $1;
  }
  close($cmdfh) 
      or $log->log_and_die("Failed to successfully complete git command to get a list of files to submit\n");
}

$log->write_to(sprintf("Found %d updated clones, %d of which have updated sequence\n", scalar(@changed_embl), scalar(@changed_seq)));
if (scalar(@changed_embl) == 0) {
  $log->write_to("No entries to submit, exiting (are you sure you ran EMBLdump.pl?)\n");
  $log->mail;
  exit(0);
}


##########################################
# There may be multiple submissions for a given release
# and we need to track all of them individually, hence
# a separate log file for each
##########################################
my @submit_logs = glob("${submit_log_prefix}.${ws_version}.*");
my $submit_version = 0;
foreach my $lfile (@submit_logs){
  $lfile =~ /\.(\d+)$/ and do {
    my $vn = $1;
    $submit_version = $vn if $vn > $submit_version;
  }
}
$submit_version++;

my $submit_log_file = "$submit_log_prefix.${ws_version}.${submit_version}";
open(my $submitlogfh, ">$submit_log_file")
    or $log->log_and_die("Could not open $submit_log_file for writing\n");
print $submitlogfh "Sequences submitted to ENA on $current_date, $current_time:\n\n";

#################################
# Collate all of the entries to be submitted
# into a single file - more efficient for upload
#
my $collated_file = sprintf("/tmp/%s_submission_%s_%d.embl", 
                            $species,
                            $ws_version,
                            $submit_version);

open(my $collatedfh,  ">$collated_file")
    or $log->log_and_die("Could not open $collated_file for writing\n");

foreach my $embl_file (@changed_embl) {
  print $submitlogfh "$embl_file\n";

  open(my $embl_fh, "$submit_repo/$embl_file")
      or $log->log_and_die("Failed to find $embl_file in $submit_repo\n");

  while(<$embl_fh>) {
    print $collatedfh $_;
  }
}
close($collatedfh) 
    or $log->log_and_die("Could not successfully complete the collation of .embl files for submission\n");
close($submitlogfh)
    or $log->log_and_die("Could not successfully close submit log file $submit_log_file\n");

##################################
# Deposit the data on the FTP site
##################################
$ftp->put($collated_file) 
    or $log->log_and_die ("FTP-put failed for $collated_file: ".$ftp->message."\n");
$ftp->quit;

$log->write_to("\nFile: $collated_file uploaded ENA ftp account\n");
$log->write_to("\nRefer to log file $submit_log_file for details on which entries were uploaded\n");


##################################
# Commit changes back to repository, to 
# ensure that it is consistent with what has
# been submitted
##################################


my $commit_cmd = sprintf("cd %s && git commit --all --message=\'ENA submission for %s, iteration %s, on %s %s\'", 
                         $submit_repo, 
                         $ws_version,
                         $submit_version,
                         $current_date,
                         defined($comment) ? "($comment)" : "");

my $tag_cmd    = sprintf("cd %s && git tag -a %s.%s -m \'Submission %s.%s, submitted on %s %s\'", 
                         $submit_repo, 
                         $ws_version, $submit_version, 
                         $ws_version, $submit_version,
                         $current_date, 
                         defined($comment) ? "($comment)" : "");
    
$log->write_to("GIT: $commit_cmd\n");
system($commit_cmd) and do {
  $log->write_to("Final commit to repository failed after successful upload\n");
  $log->write_to("You will need to rescue this situation by hand via git\n");
  $log->log_and_die("GIT repository needs rescuing\n");
};

$log->write_to("GIT: $tag_cmd\n");
system($tag_cmd) and do {
  $log->write_to("Final tagging of repository failed after successful upload and commit\n");
  $log->write_to("You will need to rescue this situation by hand via git\n");
  $log->log_and_die("GIT repository needs rescuing\n");
};

#unlink $collated_file;

$log->mail;
exit(0);


###################################
sub get_current_timestamp {
  
  my @date = localtime();

  my $date = sprintf( "%d-%02d-%02d", $date[5] + 1900, $date[4] + 1, $date[3] );
  my $time = "$date[2]:$date[1]:$date[0]";

  return ($date, $time);
}
