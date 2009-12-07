#!/usr/local/bin/perl -wT
#author ar2
#use lib "../lib";
use strict;

use vars qw($USER $PASS $DB $VALID_USERS $VALID_API_USERS $VALID_CGCNAME_USERS $SSO_USER $MAIL_NOTIFY_LIST $MAILS $LIVE);

use SangerPaths qw(core celegans);
use SangerWeb;
use NameDB_handler;
use Data::Dumper;
use CGI::Carp qw(fatalsToBrowser warningsToBrowser);
use Website::Utilities::Mail;
use File::Path;
$| = 1;

## a list of valid  IDs to use this resources
$VALID_USERS = {
		# these are the users WBPerson id
		'ar2' 		=> 1847,
		'pad' 		=> 1983,
		'mt3' 		=> 2970,
		'gw3' 		=> 4025,
		'mh6' 		=> 4036,
 #               'md9'           => 9133,
		'tbieri' 	=> 1849,
		'jspieth' 	=> 615,
		'pozersky' 	=> 1867,
		'wnash'         => 10213,
		'stlouis' 	=> 1,
		'caltech' 	=> 1,
		'cshl' 		=> 1,
		'sanger' 	=> 1,
	       };

## a list of valid SSO login names for each DB operation
$VALID_API_USERS = {
		    'query'		=> [qw(avc ar2 pad gw3 mh6 mt3 md9 tbieri jspieth wnash pozersky stlouis caltech cshl sanger)],
		    'load_file'		=> [qw(avc ar2 pad gw3 mh6 mt3 md9 tbieri jspieth wnash pozersky stlouis caltech cshl sanger)],
		    'merge_genes'	=> [qw(avc ar2 pad gw3 mt3 md9 tbieri wnash jspieth  pozersky)],
		    'split_gene'	=> [qw(avc ar2 pad gw3 mt3 md9 tbieri jspieth wnash pozersky)],
		    'new_gene'		=> [qw(avc ar2 pad gw3 mt3 md9 tbieri jspieth wnash pozersky)],
		    'kill_gene'		=> [qw(avc ar2 pad gw3 mt3 md9 tbieri jspieth wnash pozersky)],
		    'add_name'		=> [qw(avc ar2 pad gw3 mt3 md9 tbieri jspieth wnash pozersky)],
		    'remove_name'	=> [qw(avc ar2 pad gw3 mt3 md9 tbieri jspieth wnash pozersky)],
		    'change_class'	=> [qw(avc ar2 pad gw3 mt3 md9 tbieri jspieth wnash pozersky)],
		    'dump_all'          => [qw(ar2 pad gw3 mt3 md9 tbieri jspieth wnash pozersky caltech)],
		   };

## a list of valid SSO login names able to add GCG name
$VALID_CGCNAME_USERS = {
			'mt3'			=> 1,
			'ar2'			=> 1,
                        'md9'                   => 1,
			'pad'                   => 1,
			'gw3'                   => 1,
		       };

$MAILS = {
	  'gnw'                 =>      'mt3@sanger.ac.uk', #person responsible for geneace
	  'ar2'			=>	'ar2@sanger.ac.uk',
	  'pad'			=>	'pad@sanger.ac.uk',
	  'gw3'			=>	'gw3@sanger.ac.uk',
	  'mh6'			=>	'mh6@sanger.ac.uk',
	  'mt3'			=>	'mt3@sanger.ac.uk',
          'md9'                 =>      'md9@sanger.ac.uk',
	  'tbieri'		=>	'tbieri@watson.wustl.edu',
	  'jspieth'	        =>	'jspieth@watson.wustl.edu',
	  'pozersky'	        =>	'pozersky@watson.wustl.edu',
	  'wnash'               =>      'wnash@watson.wustl.edu',
	  'stlouis'	        =>	'stlouis@wormbase.org',
	  'caltech'	        =>	'caltech@wormbase.org',
	  'cshl'		=>	'cshl@wormbase.org',
	  'sanger'		=>	'sanger@wormbase.org'
	 };

## a list of people to mail when a DB operation occurs
$MAIL_NOTIFY_LIST = [qw(ar2 mt3 pad gw3 md9)];

&main();
1;


#################################################################
sub main {
  my $web = 1;
  my $path = SangerWeb->document_root();
  my $sw = SangerWeb->new( {
			    'title'  => "WormBase NameDB $DB",
			    'banner' => "Wormbase Gene Name Management<br><font color=red>This is the LIVE system. Be carefull!</font>",
			    'inifile'=> "$path/Projects/C_elegans/header.ini",
			    'author' => 'avc',
			    'onload' => 'init()',
			   });

  # determine if live or WWWdev and select database accordingly
  if ($sw->is_dev()) {
    $DB = 'test_wbgene_id;mcs4a;3307';
    $sw->banner("This is the test server");
  } else {
    $DB = 'wbgene_id;shap;3303';
  }

  $SSO_USER = $sw->username();	## for SSO
  if ( $SSO_USER =~ /^(\w+)@/) {
    $PASS = $1;
  } else {
    $PASS = $SSO_USER;
  }
  $USER = $PASS;
  if (!$SSO_USER) {
    my $url  = "http://$ENV{'HTTP_X_FORWARDED_HOST'}$ENV{'SCRIPT_NAME'}?$ENV{'QUERY_STRING'}";
    $sw->cookie($sw->cgi->cookie(	
				 '-name'    => 'sssodestination',
				 '-value'   => $url,
				 '-expires' => '+10m',
				 '-domain'  => '.sanger.ac.uk')
	       );

    $sw->redirect("https://enigma.sanger.ac.uk/sso/login");
    $sw->redirect_delay(5);
    print $sw->header({'title'  => "WormBase Gene ID Server $DB"});
    print qq(<b>You need to log in to use this resource. You will shortly be redirected to a log in page...</b>);
    print $sw->footer();
    return;
  }
	
  print $sw->header({'title'  => "WormBase Gene ID Server $DB"});
  
	
  if (!defined $VALID_USERS->{$USER}) {
    print qq(<h3>Sorry, you $USER are not authorised to access this resource. Please contact the Wormbase team</h3>);
    print $sw->footer();
    return;
  } else {
    print qq(Authenticated database user: "$USER"<BR>		);
    #send_mail('webserver', $MAILS->{'ar2'}, "user $USER", "is using nameserver");
  }

  ## get CGI parameters
  my $action   = $sw->cgi->param('action') || "query";
  my $type     = $sw->cgi->param('type');
  my $name     = $sw->cgi->param('new_name') || $sw->cgi->param('delete_name');
  my $gene_id  = $sw->cgi->param('id');
  my $merge_id = $sw->cgi->param('id_2');
  my $lookup   = $sw->cgi->param('gene');
  my $user     = $sw->cgi->param('user') || "wormbase";
  my $ispublic = $sw->cgi->param('ispublic');
  my $remark   = $sw->cgi->param('remark');
  my $upfile   = $sw->cgi->param('upfile');
  my $class    = $sw->cgi->param('class');
  my $species  = $sw->cgi->param('species');

  print_javascript();
  print_selector($action);

  if ($action eq "query") {
    &query($lookup);

  } elsif ($action =~ /new_gene/) {
    if ( is_authorised($USER,$action) == 1) {
      &new_gene($name,$type,$species, $remark);
    }

  } elsif ($action =~ /add_name/) {
    if ( is_authorised($USER,$action) == 1) {
      &add_name($name,$type,$gene_id,$ispublic,$species);
    }

  } elsif ($action =~ /kill_gene/) {
    if ( is_authorised($USER,$action) == 1) {
      &kill_gene($gene_id, $remark);
    }

  } elsif ($action =~ /split_gene/) {
    if ( is_authorised($USER,$action) == 1) {
      &split_gene($name,$type,$gene_id,$species, $remark);
    }

  } elsif ($action =~ /merge_genes/) {
    if ( is_authorised($USER,$action) == 1) {
      &merge_genes($merge_id,$gene_id);
    }
  } elsif ($action =~ /remove_name/) {
    if ( is_authorised($USER,$action) == 1) {
      &remove_name($name,$type,$gene_id,$species, $ispublic);
    }

  } elsif ($action =~ /load_file/) {
    if ( is_authorised($USER,$action) == 1) {
      &load_file($upfile);
    }

  } elsif ($action =~ /change_class/) {
    if ( is_authorised($USER,$action) == 1) {
      &change_class($name,$class,$species);
    }
  } elsif ($action =~ /dump_all/) {
    if ( is_authorised($USER,$action) == 1) {
      &dump_all('dump');
    }
  } else {
    &query();
  }

  print $sw->footer();

}
#################################################################
sub send_mail {
  my ($from, $to, $subject, $message,) = @_;

  #send_mail("webserver",
  #$MAIL_NOTIFY_LIST,
  #"Merged gene $gene_id : $merge_id",
  #"GENE MERGE\nUSER : $USER\nLIVE:retained geneID $gene_id\nDEAD: killed geneID $merge_id");
	
  Website::Utilities::Mail->new({
				 'to'      => $to,
				 'from'    => $from,
				 'subject' => ($DB =~ 'test' ? 'TEST : ' : " ")."NAMEDB: $subject",
				 'message' => $message,
				})->send(); 
}
#################################################################
sub print_javascript {

  print qq(		
		<link rel="stylesheet" type="text/css" href="/Projects/C_elegans/javascript/autosuggest.css" />
		<script type="text/javascript" src="/Projects/C_elegans/javascript/autosuggest2.js"></script>
		<script type="text/javascript" src="/Projects/C_elegans/javascript/suggestions2.js"></script>
	) if (0);

  ##  var oTextbox = new AutoSuggestControl(document.getElementById("autoq"), new StateSuggestions());

  print qq(		
		<script language="javascript">
			function init()
			{

			}
			function formSubmit()
			{
				document.forms.doAction.submit()
			}
			function validate_merge()
			{
				var agree = confirm("Are you sure you want to merge these genes?")
				if (agree) {
					return(true);
				} else {
					return(false)
				}

			}
			function validate_delete()
			{
				var agree = confirm("Are you sure you want to delete this gene?")
				if (agree) {
					return(true);
				} else {
					return(false)
				}

			}

		</script>
	);
}
#################################################################
sub is_authorised {
  my ($user, $action) = @_;
	
  if (!grep {/$PASS/} @{$VALID_API_USERS->{$action}} ) {
    print qq(
		<b>Sorry, you are not authorised to perform the following action "$action" on the gene names database</b>
		<BR><BR>
		);
    return(0);
  } else {
    return(1)
  }
}
#################################################################
sub merge_genes 
  {
    my ($merge_gene,$gene_gene) = @_;

    unless ($merge_gene && $gene_gene){
      print qq(
		<h3>Merge two existing WBGenes</h3>
		<form action="$ENV{'SCRIPT_NAME'}" method="GET">
		<BR><BR>
		Gene to stay alive  
		<INPUT TYPE="text" NAME="id" SIZE="20" MAXLENGTH="14"<br>
		Gene to remove after merge   
		<INPUT TYPE="text" NAME="id_2" SIZE="20" MAXLENGTH="14">
		<INPUT TYPE="hidden" NAME="action" VALUE="merge_genes">
		<br><br>
		<INPUT TYPE="submit" VALUE="Merge" onClick="return validate_merge()">
		<input type="reset" value="Clear Form" />		
    	</form>
		);
      print "<BR><font color=red>Please enter genes in both fields</font>" if($merge_gene or $gene_gene);
 
    } else {
      print  "attempting to merge -$merge_gene | $gene_gene-<br>";
      my $db = get_db_connection();
      if ( my $ids = $db->merge_genes($gene_gene, $merge_gene) ) {
	print "Merge complete, $merge_gene is DEAD and has been merged into gene $gene_gene <br>";
	#notify
	send_mail("webserver",[$MAILS->{$USER},$MAILS->{'gnw'},$MAILS->{'ar2'},$MAILS->{'pad'},$MAILS->{'gw3'},$MAILS->{'caltech'}],"Merged gene $gene_gene : $merge_gene", "GENE MERGE\nUSER : $USER - WBPerson". $$VALID_USERS{$USER} ."\nLIVE:retained geneID for $gene_gene - ".$ids->[0]."\nDEAD: killed geneID $merge_gene - ".$ids->[1]."\n");
      } else {
	print "Sorry, the gene merge failed<br>";
      }
    }
  }


#################################################################
sub split_gene {
  my ($name,$type,$gene_id,$species, $remark) = @_;

  unless ($type && $name && $gene_id){

    print qq(
		<h3>Split an existing WBGene</h3>
		<form action="$ENV{'SCRIPT_NAME'}" method="GET">
		<BR><BR>
		Enter the WBGene_id of the gene to split 
		<INPUT TYPE="text" NAME="id" SIZE="13" MAXLENGTH="14">
		<BR>and the new Sequence gene to create
		<INPUT TYPE="text" NAME="new_name" SIZE="13" MAXLENGTH="13" VALUE="new Sequence"><br>
Species : 
<select name="species">
<option selected value="elegans">elegans</option>
<option value="briggsae">briggsae</option>
<option value="remanei">remanei</option>
<option value="brenneri">brenneri</option>
<option value="japonica">japonica</option>
<option value="pristionchus">Pristionchus</option>
</select><P>
		<font color=gray>(Optional) Addition comment (eg instruction to nomenclature person)<br> <INPUT TYPE="text" NAME="remark" SIZE="100" MAXLENGTH="200"><BR></font>
		<INPUT TYPE="hidden" NAME="action" VALUE="split_gene">
		<INPUT TYPE="hidden" NAME="type" VALUE="Sequence">
		<br><br>
		<INPUT TYPE="submit" VALUE="Split">
		<br>if you're making a pseudogene, just create it as a new Sequence gene<br>
		</form>
		);#'
 
	      } else {
	
		my $db = get_db_connection();
		my $new_id =$db->split_gene($name, $type, $gene_id, $species);
		if ( $new_id ) {
		  my $msg = "USER : $USER\nACTION : Split $gene_id\nNEW geneId : $new_id\nNEW CDS : $type $name\n\n splitgene.pl -old $gene_id -new $name -who ". $$VALID_USERS{$USER} ." -id $new_id -load -species $species\n";
		  $msg .= "\n\n$remark" if $remark;
		  send_mail("webserver",[$MAILS->{$USER},$MAILS->{'gnw'},$MAILS->{'ar2'},$MAILS->{'pad'},$MAILS->{'gw3'},$MAILS->{'caltech'}],"Split gene $gene_id",$msg);

		  #report to screen
		  #$new_id = 'secret' unless ( $LIVE or defined $$VALID_CGCNAME_USERS{$USER});
		  print qq(Split $gene_id creating $new_id with sequence name "$name"<br>);
		} else {
		  print qq(ERROR : Cant Split $gene_id);		
		}
	      }
}

#################################################################
sub kill_gene {
  my ($gene_id,$remark) = @_;

  unless ($gene_id and $remark){

    print qq(
		<h3>Delete an existing WBGene</h3>
		<br><font color=red>*</font> If you are about to kill a gene as part of a gene merge <b>STOP</b><br>
		you DO NOT have to kill the merged gene separately<br>
		<form action="$ENV{'SCRIPT_NAME'}" method="GET">
		<BR><BR>
		Gene ID to kill [eg WBGene00001234] <INPUT TYPE="text" NAME="id" SIZE="20" MAXLENGTH="14">
		from the database<BR>
                Please give reason for removal (<font color=red>required</font>)<br> <INPUT TYPE="text" NAME="remark" SIZE="100" MAXLENGTH="200"><BR>
		<INPUT TYPE="hidden" NAME="action" VALUE="kill_gene">
		<br><br>
		<INPUT TYPE="submit" VALUE="Kill" onClick="return validate_delete()">
		<input type="reset" value="Clear Form" />		
		</form>
		);
 
  } else {
	
    my $db = get_db_connection();
    if ($db->kill_gene($gene_id)) {
      print qq(Gene "$gene_id" has been killed because \"$remark\"<br>);
			
      send_mail("webserver",[$MAILS->{$USER},$MAILS->{'gnw'},$MAILS->{'ar2'},$MAILS->{'pad'},$MAILS->{'gw3'},$MAILS->{'caltech'}],"Kill request $gene_id", "$gene_id\nRemark \"$remark\"\nWBPerson".$VALID_USERS->{$USER}."//\t$USER\n\n");
    } else {
      print qq(FAILED to kill "$gene_id" <br>);
    }
  }
}
#################################################################
sub remove_name {
  
  my ($name,$type,$gene_id, $species, $ispublic) = @_;
  unless ($type && $name && $gene_id){
	
    ## print the query form
    print qq(
		<h3>Remove name from existing gene</h3>
		<form action="$ENV{'SCRIPT_NAME'}" method="GET">
		<BR><BR>
		Remove the name 
		<SELECT NAME="type">
		  <OPTION SELECTED>Sequence
		  <OPTION>CGC
		</SELECT>
		<INPUT TYPE="text" NAME="delete_name" SIZE="15" MAXLENGTH="15">
		from gene: 
		<INPUT TYPE="text" NAME="id" SIZE="13" MAXLENGTH="14">
		<INPUT TYPE="hidden" NAME="action" VALUE="remove_name">
		<br>Species : 
<select name="species">
<option selected value="elegans">elegans</option>
<option value="briggsae">briggsae</option>
<option value="remanei">remanei</option>
<option value="brenneri">brenneri</option>
<option value="japonica">japonica</option>
<option value="pristionchus">Pristionchus</option>
</select><P><br>
		<INPUT TYPE="submit" VALUE="Remove Name">

		</form>
   		);
  } else {
    my $db = get_db_connection();
    if ( ($type eq "CGC") and (!exists $VALID_CGCNAME_USERS->{$USER}) ) {
      print qq(
			<b>Sorry, you are not authorised to remove GCG gene names from the database</b>
			<BR><BR>
			);
    }
    $gene_id = &convert_to_geneID($db,$gene_id);
    print "$gene_id $name $type";
    if ($db->remove_name($gene_id, $type, $name, $species)) {
      print "<br>removed $name from $gene_id";
      #print remaining names
      $db->printAllNames($gene_id);
      send_mail("webserver",$USER,"Remove gene name", "$USER removed a gene name (gene $gene_id had name $type $name removed)");
    } else {
      print "name removal failed<br>Names for $gene_id";
    }
  }
}


#################################################################
sub add_name {
  my ($name,$type,$gene_id,$ispublic, $species) = @_;

  unless ($type && $name && $gene_id){
	
    ## print the query form
    print qq(
			<h3>Add name to existing gene</h3>
			<form action="$ENV{'SCRIPT_NAME'}" method="GET">
			<BR><BR>
			Enter the details of the additional gene name<br><br>  
			Name type to be added: <SELECT NAME="type">
			  <OPTION SELECTED>Sequence
		);
    ## only specified users can add a CGC name
    if (exists $VALID_CGCNAME_USERS->{$USER}) {
      print qq(
			  <OPTION SELECTED>CGC
			);
    }
    print qq(
			</SELECT><br>
			Name to add: <INPUT TYPE="text" NAME="new_name" SIZE="22" MAXLENGTH="22" VALUE=""><br>
			for gene (WBGeneID or Sequence_name): <INPUT TYPE="text" NAME="id" SIZE="25" MAXLENGTH="25" VALUE=""><br>
Species : 
<select name="species">
<option selected value="elegans">elegans</option>
<option value="briggsae">briggsae</option>
<option value="remanei">remanei</option>
<option value="brenneri">brenneri</option>
<option value="japonica">japonica</option>
<option value="pristionchus">Pristionchus</option>
</select>
<INPUT TYPE="hidden" NAME="action" VALUE="add_name">
    		<INPUT TYPE="submit" VALUE="Add Name">
		);

  } else {
	
    ## if people try to hack the GET URL parameters
    if ( ($type eq "CGC") and (!exists $VALID_CGCNAME_USERS->{$USER}) ) {
      print qq(
			<b>Sorry, you are not authorised to add a GCG gene name to the database</b>
			<BR><BR>
			);
    } else {	
      my $db = get_db_connection();
      $gene_id = &convert_to_geneID($db,$gene_id);
      my $existing_names = $db->idAllNames($gene_id);
      if ( defined ($db->add_name($gene_id,$name, $type, $species)) ) {
	print qq(Added "$name" as $type name for gene $gene_id<br>);
	my $existing_CGC = $existing_names->{'CGC'};
	#foreach (keys %$existing_names) { print "$_\t".$$existing_names{$_}."<br>"}
	print qq(<br>Warning CGC name "$existing_CGC" overwritten<br>) if (defined $existing_names->{'CGC'});

	my $msg = "$type $name added to $gene_id", "USER : $USER\nWBGeneID : $gene_id\nName added : $name $type\n";
	$msg .= "\nWARNING: CGC name ".$existing_names->{'CGC'}." overwritten\n" if defined $existing_CGC;
	send_mail("webserver",[$MAILS->{$USER},$MAILS->{'gnw'},$MAILS->{'ar2'},$MAILS->{'pad'},$MAILS->{'gw3'},$MAILS->{'caltech'}],"$type added to $gene_id","$msg");
      } else {
	print "<p>FAILED: cant add name $name to $gene_id</p>";
      }
    }
  }
}
#################################################################
sub new_gene {
  my ($name,$type, $species, $remark) = @_;

  #print "type: $type, name: $name";
	
  unless ($type && $name){
	
    ## print the query form
    print qq(
    	<h3>Make a new gene</h3>
    	<form action="$ENV{'SCRIPT_NAME'}" method="GET">
		<BR><BR>
		Enter the details of the new gene<br>  
		<SELECT NAME="type">
		  <OPTION SELECTED>Sequence
                );	
    if (exists $VALID_CGCNAME_USERS->{$USER}) {
      print qq(
			  <OPTION>CGC
			);
    }
    print qq(
		</SELECT>
		<INPUT TYPE="text" NAME="new_name" SIZE="20" MAXLENGTH="20" VALUE="">
<select name="species">
<option selected value="elegans">elegans</option>
<option value="briggsae">briggsae</option>
<option value="remanei">remanei</option>
<option value="brenneri">brenneri</option>
<option value="japonica">japonica</option>
<option value="pristionchus">Pristionchus</option>
</select>
		<P>
		<font color=gray>(Optional) Addition comment (eg instruction to nomenclature person)<br> <INPUT TYPE="text" NAME="remark" SIZE="100" MAXLENGTH="200"><BR></font>
		<INPUT TYPE="hidden" NAME="action" VALUE="new_gene">

		<br><br>
    	<INPUT TYPE="submit" VALUE="Create">
    	</form>
		);

  } else {
	
    my $db = get_db_connection();
		
    my $passed_type = $type;
    if (( $passed_type eq 'PSEUDO') or ( $passed_type eq 'NCRNA')) {
      $type = 'Sequence';
    }
    if (my $id = $db->new_gene($name, $type, $species) ) {
      my $who = $VALID_USERS->{$USER};
      my $msg; 
      $msg = "WBGeneID request $name $USER","User : $USER\nType : $passed_type\nName : $name\nID : $id\n";
      if ($type eq 'CGC') {
	my ($gene_class) = $name =~ /(\w{3,4})\-\d/;
	($gene_class) = $name =~ /(\w{3,4})\(/ unless $gene_class;

	$msg .= "\n\nGene : $id\nVersion 1\nCGC_name $name Person_evidence\nPublic_name $name\nSpecies \"Caenorhabditis $species\"\nHistory Version_change 1 now WBPerson".$VALID_USERS->{$USER}." Created\nLive\nMethod Gene\nGene_class $gene_class\n";
	$msg .= "\n\n$remark\n" if $remark;
      } else {
	$msg .= "\nnewgene.pl -seq $name -who $who -load -id $id -species $species"; # line to run script to update geneace
	$msg .= " -species $species" if $species;
	$msg .= "\n\n$remark" if $remark;
	$msg .= "\n\n";
      }
		
      send_mail("webserver",[$MAILS->{$USER},$MAILS->{'gnw'},$MAILS->{'ar2'},$MAILS->{'pad'},$MAILS->{'gw3'}], "WBGeneID request $name $USER",$msg );
      #report to screen
      #$id = 'secret' unless ( $LIVE or defined $$VALID_CGCNAME_USERS{$USER});
      print "The new id for $type: $name is $id\n";
      print qq(
			<hr align="left">
			<BR><BR><BR>
			);
    } else {
      print "<p>FAILED : cant create GeneID for $type $name</p>";
    }
  }
}

#################################################################
sub query {
  my $lookup = shift;
  unless ($lookup){
    ## print the query form
    print qq(
    	<form action="$ENV{'SCRIPT_NAME'}" method="GET">
		<BR><BR>
    	  <h3>Retreive gene info</h3>
    	  Gene to retreive<br>  
    	  <INPUT TYPE="text" NAME="gene" SIZE="20" MAXLENGTH="20" VALUE="">
    	  <INPUT TYPE="hidden" NAME="action" VALUE="query">
		<br><br>
    	  <INPUT TYPE="submit" VALUE="Search">
    	</form>
		);
	
  } else {
		
    ##run the query
    my $db = get_db_connection();
		
    my $gene = $lookup;
    #$db->validate_name($gene, $type);
    ($gene) = $db->idGetByAnyName($lookup);
    unless ($gene and $gene =~ /\w+/) {
      print($lookup." does not exist in database<br>");
      return;
    }
		
    print qq(
		The Gene Name database currently holds the following information about $lookup:
		<BR><BR><BR>
		);
    $db->print_history($gene);
    $db->printAllNames($gene);
    print qq(
		<hr align="left">
		<BR><BR><BR>
		);
    #send_mail("webserver",[$MAILS->{$USER}],"query", "$USER queried for $gene");
  }

}


sub load_file {
  my $file = shift;
  unless ( $file ) {
    ## print the query form
    print qq(
    	<form action="$ENV{'SCRIPT_NAME'}" method="POST" enctype="multipart/form-data" >
		<BR><BR>
    	  <h3>Upload a query list</h3>
    	  File to upload: <INPUT TYPE=FILE NAME="upfile"><BR>
			<INPUT TYPE=SUBMIT VALUE="Submit">
			<INPUT TYPE="hidden" NAME="action" VALUE="load_file">
    	</form>
		);		
  } else {
    my $db = get_db_connection();
    #untaint file
    #		unless( $file =~ m/^(.+)$/ ) {
    #//			$db->dienice("tainted file\n");
    #//		}
    #//		my $tfile = $1;
    #		open(UL, "<$file") or $db->dienice("cant open file",$!);
    print "<TABLE border=1><THEAD>
			<TR>
				<TH>Gene_id
				<TH>CGC
				<TH>Sequence
			</THEAD>
			<TBODY>";
    open FILE,"<$file" or die "cant open $file : $!\n";
    while ( <FILE> ) {
      chomp;
      my $id = $_;
      next unless /WBGene\d{8}/;
      my( $cgc, $seq, @isoforms);
      my %names = $db->idAllNames($_);
      $cgc = ($names{'CGC'} or '-');
      $seq = ($names{'Sequence'} or '-');
			
      print "<TR><TD>$id<TD>$cgc<TD>$seq<TD>";
    }
    print "</TBODY></TABLE>";
    close FILE;
  }
}
 
sub change_class {
  my ($cds, $class, $species) = @_;
  unless( $cds and $class) {
    ## print the query form
    print qq(
    	<h3>Change Sequence gene class</h3>
    	<form action="$ENV{'SCRIPT_NAME'}" method="GET">
		<BR><BR>
		Enter the details of the gene to change<br>Convert Sequence gene
		<INPUT TYPE="text" NAME="new_name" SIZE="15" MAXLENGTH="12" VALUE="">
		<p>Change to . . <p>
		<input type="radio" name="class" value="CDS"> CDS<br>
		<input type="radio" name="class" value="pseudogene" checked> Pseudogene<br>
		<input type="radio" name="class" value="transcript"> non-coding transcript<br>
		<input type="radio" name="class" value="transposon"> transposon<br>
		Species : <select name="species">
<option selected value="elegans">elegans</option>
<option value="briggsae">briggsae</option>
<option value="remanei">remanei</option>
<option value="brenneri">brenneri</option>
<option value="japonica">japonica</option>
<option value="pristionchus">Pristionchus</option>
</select>
		
		<INPUT TYPE="hidden" NAME="action" VALUE="change_class">
		<br><br>
    	<INPUT TYPE="submit" VALUE="Change Class">
    	</form>
		);

  } else {
    my $db = get_db_connection();
    $db->validate_name($cds, 'Sequence', $species);
    my $gene = $db->idGetByTypedName('Sequence', $cds); #these classes wont have CDS names

    if ( $gene->[0] ) {		
      #kill transposon genes
      if ( $class eq 'transposon') {
	&kill_gene($gene->[0], "made in to transposon");
      } else {
      my $msg = "$cds converted to $class - $USER\nThis does not affect Nameserver DB\n\nchangegene.pl -seq $cds -who ".$VALID_USERS->{$USER}." -load -class\n\nRemember you need to add a 2 letter change code eg. CP after -class";
	send_mail("webserver",[$MAILS->{$USER},$MAILS->{'gnw'},$MAILS->{'ar2'},$MAILS->{'pad'},$MAILS->{'gw3'},$MAILS->{'caltech'}],"$cds to $class", $msg);
	print "changing $cds to $class.";
      }
    } else {
      print "$cds is not a valid $class name - no changes have been made<br>";
    }
  }
}


sub dump_all {
  my $dump = shift;
  if ( $dump ) {
    # iterate over all genes and print details
    my $db = get_db_connection();
    #		my $all = $db->allLiveIds;
    #		my $tmpfile ="/tmp/nameDB.$$";
    #		open (TMP,">$tmpfile") or croak ("cant open file $tmpfile\t:$!");
    #		foreach my $gene (@$all) {
    #			print TMP "$gene\n";
    #		}
    #		close TMP;
    #		&load_file($tmpfile);
    my $query =<<END;
SELECT primary_identifier.object_public_id, name_type_name, secondary_identifier.object_name 
FROM primary_identifier, secondary_identifier, name_type 
WHERE secondary_identifier.object_id = primary_identifier.object_id 
		AND secondary_identifier.name_type_id = name_type.name_type_id 
		AND primary_identifier.object_live = 1
ORDER BY object_public_id;
END
    my $sth = $db->dbh->prepare($query);
    $sth->execute or die "Unable to execute query: $db->errstr\n";
    my $row;

    my %gene_data;
    while ($row = $sth->fetchrow_arrayref) {
      #print "$row->[0]\t$row->[1]\t$row->[2]<br>";
      next if ( ($row->[1] eq 'CDS') or ($row->[1] eq 'Public_name') );
      $gene_data{$row->[0]}->{$row->[1]} = $row->[2];
    }
    $sth->finish;

    #write a new version of webpage for stl
    my $path = SangerWeb->document_root()."/tmp/Projects/C_elegans/LOCI";
    mkpath $path unless -e $path;
    my $gene2mol = "$path/genes2molecularnamestest.txt";
    open (M2G,">$gene2mol") or die "cant open $gene2mol : $!\n";
    foreach my $gene (sort keys %gene_data) {
      print M2G "\n$gene";
      foreach my $type ( sort keys %{$gene_data{$gene}} ) {
	print M2G "\t".$gene_data{$gene}->{$type};
      }	
    }
    close M2G;	
    print qq(<a href="http://www.sanger.ac.uk/tmp/Projects/C_elegans/LOCI/genes2molecularnamestest.txt">Updated here</a>);
    print qq( <meta http-equiv="REFRESH" content="0; URL=http://www.sanger.ac.uk/tmp/Projects/C_elegans/LOCI/genes2molecularnamestest.txt">);
  } else {
    print qq( 
			<h3>Print page of all live genes</h3>
			<form action="$ENV{'SCRIPT_NAME'}" method="GET">
			<INPUT TYPE="hidden" NAME="action" VALUE="dump_all">
			<br><br>
			<INPUT TYPE="submit" VALUE="Dump"
		</form>
		);
  }
}
#################################################################
sub print_selector {
  my ($action) = @_;

  my $qs = "";
  my $ng = "";
  my $an = "";
  my $kg = "";
  my $sg = "";
  my $mg = "";
  my $rn = "";
  my $lf = ""; my $cc = ""; my $da = "";
  if ($action eq "query") {
    $qs = " selected";
  }
  ;
  if ($action eq "new_gene") {
    $ng = " selected";
  }
  ;
  if ($action eq "add_name") {
    $an = " selected";
  }
  ;
  if ($action eq "kill_gene") {
    $kg = " selected";
  }
  ;
  if ($action eq "split_gene") {
    $sg = " selected";
  }
  ;
  if ($action eq "merge_genes") {
    $mg = " selected";
  }
  ;
  if ($action eq "remove_name") {
    $rn = " selected";
  }
  ;
  if ($action eq "load_file") {
    $lf = " selected";
  }
  ;
  if ($action eq "change_class") {
    $cc = " selected";
  }
  ;
  if ($action eq "dump_all") {
    $da = " selected";
  }
  ;


  print qq(
    What do you want to do ?  <br><br>
    <form name="doAction" action="$ENV{'SCRIPT_NAME'}" method="GET">
    Select action to perform:
  	<SELECT NAME="action" onChange="formSubmit()">
    	<OPTGROUP LABEL="Gene information">
    	  <OPTION $qs LABEL="Find gene information" value="query">Search for gene information</OPTION>
    	</OPTGROUP>
	);

  if (grep {/$USER/} @{$VALID_API_USERS->{$action}} ) {
    print qq(
    	<OPTGROUP LABEL="Request a new gene ID">
    	  <OPTION $ng LABEL="new_gene" value="new_gene">Request a new WBGeneID</OPTION>
    	</OPTGROUP>
		);
  }

  if (grep {/$USER/} @{$VALID_API_USERS->{$action}} ) {
    print qq(
    	<OPTGROUP LABEL="Delete an existing gene">
    	  <OPTION $kg LABEL="kill_gene" value="kill_gene">Kill a WBGeneID</OPTION>
    	</OPTGROUP>
		);
  }

  if (grep {/$USER/} @{$VALID_API_USERS->{$action}} ) {
    print qq(
    	<OPTGROUP LABEL="Update gene names">
    	  <OPTION $an LABEL="add_name" value="add_name">Add a gene name</OPTION>
    	  <OPTION $rn LABEL="remove_name" value="remove_name">Remove a gene name</OPTION>
    	</OPTGROUP>
		);
  }

  if (grep {/$USER/} @{$VALID_API_USERS->{$action}} ) {
    print qq(
    	<OPTGROUP LABEL="Merge/split genes">
    	  <OPTION $mg LABEL="merge_genes" value="merge_genes">Merge two genes</OPTION>
    	  <OPTION $sg LABEL="split_gene" value="split_gene">Split a gene</OPTION>
    	</OPTGROUP>
		);
  }
	
  if (grep {/$USER/} @{$VALID_API_USERS->{$action}} ) {
    print qq(
    	<OPTGROUP LABEL="Load file">
    	  <OPTION $lf LABEL="load file" value="load_file">List of queries from file</OPTION>
    	</OPTGROUP>
		);
  }
		
  if (grep {/$USER/} @{$VALID_API_USERS->{$action}} ) {
    print qq(
   	<OPTGROUP LABEL="Miscellaneous">
  		   <OPTION $cc LABEL="change class" value="change_class">Change class</OPTION>
  		   <OPTION $da LABEL="dump all" value="dump_all">Dump all</OPTION>
   	</OPTGROUP>
		);
  }		
  print qq(
    </SELECT>
    <INPUT TYPE="submit" VALUE="Submit">
    </form>
	<BR><BR>
	<HR align="left">
	);
}

#make sure gene names are correct case
sub fix_case
  {
    my ($type, $name) = @_;
    if ( $type eq 'CDS' ) {
      my @data = split(/\./,$name);
      return (uc $data[0]).".$data[1]";
    } elsif ( $type eq 'CGC' ) {
      return lc $name;
    } elsif ( $type eq 'Gene' ) {
      /(\d+$)/;
      return "WBGene$1";
    } else {
      #$db->dienice($type is)
    }
  }

#################################################################
sub get_db_connection {
    my $path = SangerWeb->document_root();
  my $DOMAIN = 'Gene';
  my $db = NameDB_handler->new($DB,$USER,$PASS,$path);
	
  $db || return(undef);
  $db->setDomain($DOMAIN);
	
  $db->web(1);		# turn on web reporting
  return($db);
}

#################################################################

#This is to allow the web page to accept any name for a gene but pass the geneID to NameDB_handler.
sub convert_to_geneID {
  my $db = shift;
  my $id = shift;
  my $id_search = $db->idGetByAnyName($id)->[0];
  my $gene_id = $id_search ? $id_search : $id; #allow any name type to be added to
  return $gene_id;
}







