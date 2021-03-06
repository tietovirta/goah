#!/usr/bin/perl -w -CSDA

=begin nd

Package: goah::Modules::Invoice

  Functions to create, modify and print invoice information. Functions
  rely quite heavily to Productmanagement -funtions to access product
  information.

About: License

  This software is copyright (c) 2009 by Tietovirta Oy and associates.
  See LICENSE and COPYRIGHT -files for full details.

About: See also

  <goah::Modules::Productmanagement>

=cut

package goah::Modules::Invoice;

use Cwd;
use Locale::TextDomain ('Invoice', getcwd()."/locale");

use strict;
use warnings;

use goah::Modules::Customermanagement;
use goah::Modules::Productmanagement;
use goah::GoaH;


#
# Hash: invoicestates
#
#   Defines possible states for the invoice. *NOTE:* This variable
#   should be removed soon.
#
my %invoicestates = ( 	0 => __("Open"),
			1 => __("Sent"),
			2 => __("Remark1"),
			3 => __("Remark2"),
			4 => __("Closed, payment received"),
			5 => __("Closed, cash payment"),
			6 => __("Closed, card payment") );

#
# String: uid
#
#   User id, get's stored via Start() -function
#
my $uid='';
my $settref='';


#
# Function: Start
#
# Start the actual module. Module process is controlled via HTTP
# variables which are created internally inside the module.
#
# Parameters:
#
#   None
#
# Returns:
#
#   Reference to hash array which contains variables for Template::Toolkit
#   process for the module.
#
sub Start {

	$uid = $_[1];
	$settref = $_[2];

	my %variables;

	$variables{'function'} = 'modules/Invoice/invoices';
	$variables{'module'} = 'Invoice';
	$variables{'gettext'} = sub { return __($_[0]); };
        $variables{'formatdate'} = sub { goah::GoaH::FormatDate($_[0]); };
	$variables{'invoicestates'} = \%invoicestates;

	$variables{'customers'}=goah::Modules::Customermanagement->ReadAllCompanies(1);
	$variables{'companyinfo'} = sub { goah::Modules::Customermanagement::ReadCompanydata($_[0],1) };
	$variables{'locationinfo'} = sub { goah::Modules::Customermanagement::ReadLocationdata($_[0]) };
	$variables{'locations'} = sub { goah::Modules::Customermanagement::ReadCompanylocations($_[0]) };
	$variables{'products'} = sub { goah::Modules::Productmanagement::ReadData('products',,$uid,$settref) };
	$variables{'productinfo'} = sub { goah::Modules::Productmanagement::ReadData('products',$_[0],$uid,$settref) };

	$variables{'paymentconditions'}=goah::Modules::Customermanagement::ReadSetup('paymentcondition');

	my $total = sub { ReadInvoiceTotal($_[0]) }; 
	$variables{'readtotal'} = $total;

	my $q = CGI->new();
	my $tmp;
	if($q->param('action')) {

		if($q->param('action') eq 'show') {

			$tmp = ReadInvoices($q->param('target'));
			$variables{'invoice'} = $tmp;

			my $ordernumber = $tmp->ordernumber;

			# Change date today if needed and update also due value
			my $now = POSIX::strftime("%Y-%m-%d", localtime);
			my $created = $tmp->created;

			if (($tmp->state == 0) && ($tmp->invoicenumber == 0) && ($now gt $created)) {

				$variables{'invoice'}{'created'} = $now;

				my @created_tmp = split("-",$now);    
				my ($dyear,$dmon,$dmday) = Add_Delta_Days($created_tmp[0],$created_tmp[1],$created_tmp[2],$tmp->payment_condition);    
				my $due = sprintf("%04d-%02d-%02d",$dyear,$dmon,$dmday);    
				
				$variables{'invoice'}{'due'} = $due;
			}

			$tmp = ReadInvoicerows($q->param('target'));
			$variables{'invoicerows'} = $tmp;

			$tmp = ReadInvoicehistory($q->param('target'));
			$variables{'invoicehistory'} = $tmp;
	
			$variables{'function'} = 'modules/Invoice/invoiceinfo';

			# Search selected invoice files
                     	use goah::Modules::Files;
              	        $variables{'invoicefiles'} = goah::Modules::Files->GetFileRows($q->param('target'),'');

			# Search Basket files
              	       	$variables{'basketfiles'} = goah::Modules::Files->GetFileRows($ordernumber,'');

        		# Get GoaH internal users email-addresses
        		use goah::Modules::Systemsettings;
        		$variables{'goah_users'} = goah::Modules::Systemsettings->ReadOwnerPersonnel;

                     	# Actions if we are returning from files.cgi
                      	if ($q->param('files_action')) {

                      		if ($q->param('status') eq 'success') {
                    
                      			my $success_message; 
                              		if ($q->param('files_action') eq 'upload') {$success_message = "File uploaded succesfully"}
                               		if ($q->param('files_action') eq 'delete') {$success_message = "File deleted succesfully"}

                              		goah::Modules->AddMessage('info',"$success_message");
                   		}

                              	if ($q->param('status') eq 'error') {

                                   	# Get and process error
                                       	my $tmp_msg = $q->param('msg');
                                      	my $error_message = ucfirst($tmp_msg);
                                      	$error_message =~ s/_/ /g;
                                        
                                     	goah::Modules->AddMessage('error',"ERROR! $error_message");
                                                        
                             	}
                  	}


		} elsif($q->param('action') eq 'addevent') {

			if(AddEventToInvoice($q->param('target'),$q->param('information'))) {
				goah::Modules->AddMessage('info',__("Event added to invoice"));
			} else {
				goah::Modules->AddMessage('error',__("Can't add event to invoice."));
			}

			
			$tmp = ReadInvoices($q->param('target'));
			$variables{'invoice'} = $tmp;

			$tmp = ReadInvoicerows($q->param('target'));
			$variables{'invoicerows'} = $tmp;

			$tmp = ReadInvoicehistory($q->param('target'));
			$variables{'invoicehistory'} = $tmp;

			$variables{'function'} = 'modules/Invoice/invoiceinfo';

		} elsif($q->param('action') eq 'updateinvoice') {

			my $state;

			if($q->param('invoicetobilling')) {
				$state=1;
			} elsif($q->param('invoicetocashreceipt')) {
				$state=5;
			} elsif($q->param('invoicetocardreceipt')) {
				$state=6;
			} elsif($q->param('invoicebacktobasket')) {
		
				# Convert unsent invoice back to basket

				# First, check that invoice status is convertable
				my $invoice = ReadInvoices($q->param('target'));
				unless($invoice->id eq $q->param('target')) {
					goah::Modules->AddMessage('error',__("Can't read invoice information. Can't revert invoice into an basket."),__FILE__,__LINE__);
				} else {
					my $ok=1;
					unless($invoice->state eq "0") {
						goah::Modules->AddMessage('error',__("Can't delete invoice! Invoice already sent!"));
						goah::Modules->AddMessage('debug',"Invoice state: ".$invoice->state,__FILE__,__LINE__);
						$ok=0;
					}
					# Actually delete the invoice and referral included in it
					use goah::Modules::Referrals;
					my $delref = goah::Modules::Referrals->DeleteReferral($invoice->referralid);

					if($delref==0 && $ok==1) {
						goah::Modules->AddMessage('info',__("Referral removed."));
						if(DeleteInvoice($q->param('target'))) {
							goah::Modules->AddMessage('info',__("Invoice converted to basket"),__FILE__,__LINE__);
						} else {
							goah::Modules->AddMessage('error',__("Couldn't convert invoice to basket!"),__FILE__,__LINE__);
						}
					} elsif($ok==1) {
						goah::Modules->AddMessage('error',__("Couldn't delete referral. Leaving invoice untouched!"));
					}
				}

			}

			unless($q->param('invoicebacktobasket')) {
				if(UpdateInvoiceinfo($q->param('target'),$state)) {
					goah::Modules->AddMessage('info',__("Invoice information updated."));
				} else {
					goah::Modules->AddMessage('error',__("Can't update invoice information!"));
				}

				$tmp = ReadInvoices($q->param('target'));
				$variables{'invoice'} = $tmp;

				$tmp = ReadInvoicerows($q->param('target'));
				$variables{'invoicerows'} = $tmp;

				$tmp = ReadInvoicehistory($q->param('target'));
				$variables{'invoicehistory'} = $tmp;

				$variables{'function'} = 'modules/Invoice/invoiceinfo';
			} else {

				$variables{'function'} = 'modules/Invoice/invoices';
				$variables{'invoices'} = ReadInvoices();
				my @tmp;
				@tmp=qw(0 1 2 3);
				my $csvurl.="&states=".join("&states=",@tmp);
				$variables{'csvurl'}=$csvurl;
				$variables{'search_states'}=\@tmp;
			}

		} elsif($q->param('action') eq 'invoicetobilling') {

			if(UpdateInvoiceinfo($q->param('target'))) {
				goah::Modules->AddMessage('info',__("Invoice transferred to billing. Don't forget to print out PDF!"));
			} else {
				goah::Modules->AddMessage('error',__("Can't update invoice information!"));
			}

			$tmp = ReadInvoices($q->param('target'));
			$variables{'invoice'} = $tmp;
			$tmp = ReadInvoicerows($q->param('target'));
			$variables{'invoicerows'} = $tmp;
			$tmp = ReadInvoicehistory($q->param('target'));
			$variables{'invoicehistory'} = $tmp;
			$variables{'function'} = 'modules/Invoice/invoiceinfo';

		} elsif( ($q->param('action') eq 'invoicetocashreceipt') || $q->param('action') eq 'invoicetocardreceipt') {
			if(UpdateInvoiceinfo($q->param('target'))) {
				if($q->param('action') eq 'invoicetocashreceipt') {
					goah::Modules->AddMessage('info',__("Cash payment received. Don't forget to print out PDF!"));
				} else {
					goah::Modules->AddMessage('info',__("Card payment received. Don't forget to print out PDF!"));
				}
			} else {
				goah::Modules->AddMessage('error',__("Can't update invoice information!"));
			}
                        $tmp = ReadInvoices($q->param('target'));
                        $variables{'invoice'} = $tmp;
                        $tmp = ReadInvoicerows($q->param('target'));
                        $variables{'invoicerows'} = $tmp;
                        $tmp = ReadInvoicehistory($q->param('target'));
                        $variables{'invoicehistory'} = $tmp;
                        $variables{'function'} = 'modules/Invoice/invoiceinfo';

		} elsif($q->param('action') eq 'invoicepaymentreceived') {
			if(UpdateInvoiceinfo($q->param('target'))) {
				goah::Modules->AddMessage('info',__("Invoice payment received."));
			} else {
				goah::Modules->AddMessage('info',__("Card payment received. Don't forget to print out PDF!"));
			}
                        $tmp = ReadInvoices($q->param('target'));
                        $variables{'invoice'} = $tmp;
                        $tmp = ReadInvoicerows($q->param('target'));
                        $variables{'invoicerows'} = $tmp;
                        $tmp = ReadInvoicehistory($q->param('target'));
                        $variables{'invoicehistory'} = $tmp;
                        $variables{'function'} = 'modules/Invoice/invoiceinfo';

		} else {  

			goah::Modules->AddMessage('error',__("Module doesn't have function ")."'".$q->param('action')."'.");
			$variables{'function'} = 'modules/blank';
		}

	} else {
		if($q->param('showrows') && $q->param('showrows') eq 'rows') {
			if($q->param('customer') eq '*') {
				goah::Modules->AddMessage('warn',__("Can't search invoice rows unless customer is selected!"));
				$variables{'invoices'} = ReadInvoices();
			} else {
				$variables{'function'} = 'modules/Invoice/invoices.rows';
				$variables{'invoices'} = ReadInvoices('',1);
			}
		} else {
			$variables{'invoices'} = ReadInvoices();
		}

		my @tmp;
		my $csvurl="module=Invoice";
		if($q->param('subaction') eq 'search') {
			@tmp=$q->param('states');
			$variables{'search_startdate'}=$q->param('fromdate');
			$variables{'search_enddate'}=$q->param('todate');
			$variables{'datesearch'}=$q->param('datesearch');
			$variables{'sortby'}=$q->param('sortby');
			$variables{'sortdir'}=$q->param('sortdir');
			if($q->param('customer')) {
				$variables{'search_customer'}=$q->param('customer');
			} else {
				$variables{'search_customer'}='*';
			}
			$csvurl.="&subaction=search&";
			$csvurl.="fromdate=".$q->param('fromdate')."&";
			$csvurl.="todate=".$q->param('todate')."&";
			$csvurl.="customer=".$variables{'search_customer'};
		} else {
			@tmp=qw(0 1 2 3);
		}
		$csvurl.="&states=".join("&states=",@tmp);
		$variables{'csvurl'}=$csvurl;
		$variables{'search_states'}=\@tmp;
	}



	return \%variables;
}


#
# Function: NewInvoice
#
# Create new invoice. Invoice is always created from basket, so 
# we'll read invoice information via basket.
#
# Parameters:
#
#   id - ID number for basket which is used to create invoice
#
# Returns:
#  
#   success - 1
#   fail - 0
#
sub NewInvoice {

	# This function is called outside of the package internal namespace
	# so we need to handle that case as well.
	if($_[0]=~/goah::Modules::Invoice/) {
		shift;
	}

	unless($_[0]) {
		goah::Modules->AddMessage('error',__("Can't create new invoice!")." ".__("Referral id is missing!"));
		return 0;
	}

	use goah::Database::Invoices;

	#
	# THIS NEEDS TO BE CHANGED TO GET DATA FROM Referrals -MODULE ITSELF!
	# NOT DIRECTLY FROM THE DATABASE!
	use goah::Database::Referrals;
	my $refinfo = goah::Database::Referrals->retrieve($_[0]);
	
	use goah::Modules::Basket;
	my @searchbaskets;
	push(@searchbaskets,$refinfo->orderid);
	my $basketinforef = goah::Modules::Basket::ReadBaskets(\@searchbaskets);

	unless($basketinforef) {
		goah::Modules->AddMessage('error',__("Can't create new invoice!")." ".__("Can't read order contents!"));
		return 0;
	}

	my %basketinfo=%$basketinforef;

	# Search for next invoice number first
	#my @tmp = goah::Database::Invoices->retrieve_all_sorted_by('invoicenumber');
	#my $lastnumber = pop(@tmp);
	#	# We need atleast 3 digit invoice number so that referral numbers get calculated correctly.
	#if($lastnumber && $lastnumber>=100) {
	#	$lastnumber = $lastnumber->invoicenumber;
	#} else {
	#	$lastnumber = 100;
	#}

	my $lastnumber = '000';
	my $refnro = '000';
	#my $refnro = CreateReferencenumber($lastnumber);
	#if($refnro == 0) {
	#	goah::Modules->AddMessage('error',__("Can't get reference number for invoice number! Can't create invoice!"),__FILE__,__LINE__);
	#	return 0;
	#}
	
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $created = sprintf("%04d-%02d-%02d",$year+1900,$mon+1,$mday);

	use Date::Calc qw(Add_Delta_Days);
	my $customerdata = goah::Modules::Customermanagement->ReadCompanydata($basketinfo{'companyid'});
	my $due;
	if($customerdata == 0) {
		goah::Modules->AddMessage('error',__("Couldn't read customer data from the database. Can't calculate due date."));
		$due = $created;
	} else {
		my ($dyear,$dmon,$dmday) = Add_Delta_Days($year+1900,$mon+1,$mday,$customerdata->payment_condition);
		$due = sprintf("%04d-%02d-%02d",$dyear,$dmon,$dmday);
	}


	my $invoice = goah::Database::Invoices->insert( { 	invoicenumber => $lastnumber,
								referralid => $refinfo->id,
								companyid => $basketinfo{'companyid'},
								locationid => $basketinfo{'locationid'},
								billingid => $basketinfo{'billingid'},
								state => '0',
								referencenumber => $refnro,
								created => $created,
								due => $due,
								payment_condition => $customerdata->payment_condition,
								customerreference => $customerdata->customerreference, 
								ordernumber => $basketinfo{'id'} });
	
	# Read rows from basket as well, so they can be written into invoice rows
	my $brows_pointer = goah::Modules::Basket::ReadBasketrows($refinfo->orderid,-1);
	my %basketrows = %$brows_pointer;

	#
	# THIS NEEDS TO BE CHANGED TO GET DATA FROM Referrals -MODULE ITSELF!
	# NOT DIRECTLY FROM THE DATABASE!
	use goah::Database::Referralrows;
	my $refrow;
	
	goah::Modules->AddMessage('debug',"Writing ".scalar(keys %basketrows)." rows to invoice");
	foreach my $rowkey (keys %basketrows) {
		if($rowkey<0) { next; }
		my @tmp = goah::Database::Referralrows->search_where({ rowid => $basketrows{$rowkey}{'id'} });
		my $refrow = $tmp[0];
		unless( AddRowToInvoice($invoice->id,$basketrows{$rowkey}{'productid'},$basketrows{$rowkey}{'purchase'},$basketrows{$rowkey}{'sell'},$refrow->sent,$basketrows{$rowkey}{'rowinfo'},$basketrows{$rowkey}{'productcode'},$basketrows{$rowkey}{'productname'},$basketrows{$rowkey}{'vatvalue'}) ) {
			goah::Modules->AddMessage("debug","Insert check failed");
			return 0;
		}
	}


	# Add event to invoice about creation
	AddEventToInvoice($invoice->id,__("Invoice created"),$invoice->state);
	
	# Everything went ok, return 0 and let Basket module take care of 
	# removing basket which is now transferred to invoice
	return 1;
	
}

#
# Function: CreateReferencenumber
#
# Create reference number for the bill from invoice number. This calculation
# creates reference number fit for Finnish banking system, other countries
# may need to create something different.
#
# Parameters:
#
#   id - ID for invoice
#
# Returns:
#
#   success - Reference number for invoice
#   failure - 0
#
sub CreateReferencenumber {

	unless($_[0]) {
		goah::Modules->AddMessage('error', __("Can't create reference number for the bill! Invoice number is missing!"));
		return 0;
	}

	# Code derived from GoaH 1.2.5, I'll trust that ;)

	my $ref=$_[0];
	my $counter=0;
	my $sum=0;
	my $csum;
	my $len = length($ref);
	my @multipliers = (7, 3, 1);

	if($len > 19) {
		goah::Modules->AddMessage('error',__("Invoice number too long! Can't create reference number!"));
		return 0;
	}

	if($len < 3) {
		$ref = sprintf("%02d",$ref);
	}

	my $csumref=$ref;
	while($counter < $len) {
		$sum += ($csumref % 10) * $multipliers[($counter % 3)];
		$csumref = int($csumref / 10);
		$counter++;
	}

	$csum = (10 - ($sum % 10)) % 10;

	return $ref.$csum;

}

#
# Function: AddRowToInvoice
#
# Add row to invoice based on parameters
#
# Parameters:
#  
#   invoiceid - ID number for invoice (from database)
#   productid - ID number for product (from database)
#   purchase - Purchase price for unit (float)
#   sell - Sell price for unit (float)
#   amount - Amount to be added (float)
#   rowinfo - Additional information for the row
#   product code - Product code
#   product name - Product name
#   product vat - Vat value for product
#
# Returns:
#
#   Always 1 (why?)
#
sub AddRowToInvoice {

	unless($_[0]) {
		goah::Modules->AddMessage('error',__("Can't add row to invoice!")." ".__("Invoice id is missing!"));
		return 1;
	}

	unless($_[1]=~/^[0-9]+$/) {
		goah::Modules->AddMessage('error',__("Can't add row to invoice!")." ".__("Product id is missing!"));
		goah::Modules->AddMessage('debug',"Product id: ".$_[1]);
		return 1;
	}

	use goah::Database::Invoicerows;
	goah::Database::Invoicerows->insert({ 	invoiceid => $_[0],
						productid => $_[1],
						purchase => $_[2],
						sell => $_[3],
						amount => $_[4],
						rowinfo => $_[5],
						code => $_[6],
						name => $_[7],
						vat => $_[8]});
	
	return 1;

}

#
# Function: ReadInvoices
#
# Read either all invoices or single invoice from database.
#
# Parameters
#
#   id - If ID is empty read all invoices, either read invoice by ID number
#   rows - If 1 include invoice rows into hash
#   pdf - If 1 return data formatted correctly for PDF
#
sub ReadInvoices {

	use goah::Db::Invoices::Manager;
	my @data;
	
	# Search all invoices
	if(!($_[0]) || $_[0] eq '') {

		my %dbsearch;

		my @states= qw(0 1 2 3);
		my $datestart=0;
		my $dateend=0;
		my $customer='';
		my %totalsum;

		my $q = CGI->new;
		if($q->param('subaction') eq 'search') {
			@states=$q->param('states');
		}
		$dbsearch{'state'}=\@states;

		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		$year+=1900;
		$mon++;

		if($q->param('fromdate')) {
			$datestart=$q->param('fromdate');
			if($datestart=~/[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{4}/ ) {
				# OK!
			} elsif($datestart=~/[0-9]{1,2}\.[0-9]{1,2}\./) {
				$datestart.=$year;
			} else {
				goah::Modules->AddMessage('error',__("Start date isn't formatted correctly. Ignoring filter."));
				$datestart='';
			}
		}

		if($q->param('todate')) {
			$dateend=$q->param('todate');
			if($dateend=~/[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{4}/) {
				# OK!
			} elsif($dateend=~/[0-9]{1,2}\.[0-9]{1,2}\./) {
				$dateend.=$year;
			} else {
				goah::Modules->AddMessage('error',__("End date isn't formatted correctly. Ignoring filter."));
				$dateend='';
			}
		}

		my @searchdate=split(/\./,$datestart);
		$datestart=sprintf("%04d-%02d-%02d",$searchdate[2],$searchdate[1],$searchdate[0]);
		@searchdate=split(/\./,$dateend);
		$dateend=sprintf("%04d-%02d-%02d",$searchdate[2],$searchdate[1],$searchdate[0]);

		# Search by due/created
		my $duecreated='created';
		$duecreated='due' if ($q->param('datesearch') && $q->param('datesearch') eq 'due');

		goah::Modules->AddMessage('debug',"Duecreated: $duecreated, http-param: ".$q->param('datesearch'),__FILE__,__LINE__);

		# Start date, no end date 
		if($datestart>0 && $dateend==0) {
			$dbsearch{$duecreated} = { ge => $datestart };
		} 

		# End date, no start date
		if($dateend>0 && $datestart==0) {
			$dbsearch{$duecreated} = { lt => $dateend };
		}

		# Both start and end date
		if($datestart>0 && $dateend>0) {
			$dbsearch{'and'} = [ $duecreated => { ge => $datestart }, $duecreated => { le => $dateend } ];
		}

		if($q->param('customer') && $q->param('customer')>0) {
			$dbsearch{'companyid'}=$q->param('customer');
		}

		my $sortby='state,due';
		my $sortdir='ASC';

		if($q->param('sortby')) {
		
			if( $q->param('sortby') eq 'date') {
			
				$sortby='due';
				if($duecreated eq 'created') {
					$sortby='created';
				} 
			}

			if( $q->param('sortby') eq 'number') {
				$sortby='invoicenumber';
			}
		}

		if($q->param('sortdir') && $q->param('sortdir') eq 'desc') {
			$sortdir='DESC';
		}
		
		#my $sortrules="state,".$sortby." ".$sortdir;
		my $sortrules=$sortby." ".$sortdir;
		goah::Modules->AddMessage('debug',"Sort by: $sortrules");
		my $datap=goah::Db::Invoices::Manager->get_invoices(\%dbsearch, sort_by => $sortrules );
		@data=@$datap;

		my $pdf='';
		if($_[2]) {
			if($_[2] eq 1) {
				$pdf=2;
			} else {
				$pdf=$_[2];
			}
		}

		goah::Modules->AddMessage('debug',"States: @states",__FILE__,__LINE__);
		goah::Modules->AddMessage('debug',"Search parameters: ".join(" - ",keys(%dbsearch)),__FILE__,__LINE__);
		#goah::Modules->AddMessage('debug',"And: ".join(" - ",keys($dbsearch{'and'})),__FILE__,__LINE__);
		my %invoices;
		my $add;
		my $sortcounter=1000000;
		foreach my $inv (@data) {

			my $t = goah::Modules::Invoice->ReadInvoiceTotal($inv->id,$pdf);
			my %tot=%$t;
			$totalsum{'vat0'}+=$tot{'vat0'};
			$totalsum{'inclvat'}+=$tot{'inclvat'};
			$totalsum{'vat'}+=$tot{'vat'};

			#$invoices{$inv->invoicenumber.'.'.$inv->id}=$inv;
			$sortcounter++;
			$invoices{$sortcounter}=$inv;
		}

		# Check and if needed read invoice rows into hash as well
		if($_[1] && $_[1]==1) {

			foreach my $k (keys(%invoices)) {
				my $i=$invoices{$k};
				my $r = goah::Modules::Invoice->ReadInvoicerows($i->id,$pdf);
				my %rows=%$r;
				$invoices{'rows'}{$k}=$r;
			}

		}


		$invoices{'total'}{'vat0'}=goah::GoaH->FormatCurrencyNopref($totalsum{'vat0'},0,0,'out',0,$pdf);
		$invoices{'total'}{'inclvat'}=goah::GoaH->FormatCurrencyNopref($totalsum{'inclvat'},0,0,'out',1,$pdf);
		$invoices{'total'}{'vat'}=goah::GoaH->FormatCurrencyNopref($totalsum{'vat'},0,0,'out',0,$pdf);
		return \%invoices;
	} else {
		@data = goah::Database::Invoices->retrieve($_[0]);
		if(scalar(@data) == 0) {
			return 0;
		}

		return $data[0];
	}
	return 0;
}


#
# Function: ReadInvoicerows
#
# Read all rows and their data for spesific invoice.
#
# Parameters:
#
#   id - Invoice ID -number from database
#   uid - User ID to use for settings retrieval
#   pdf - If 1 return nubmers formatted correctly for PDF output, higher than 1 uses given number of decimals
#
# Returns:
#
#   Fail - 0
#   Success - Hash reference to invoice data
#
sub ReadInvoicerows {


	if($_[0]=~/goah::Modules::Invoice/) {
		shift;
	}

	unless($_[0]) {
		goah::Modules->AddMessage('error',__("Can't read rows for invoice!")." ".__("Invoice id is missing!"));
		return 0;
	}

	if($uid eq '') {
		if($_[1]) {
			$uid = $_[1];
		} else {
			goah::Modules->AddMessage('error',__("Can't read rows for invoice!")." ".__("UID is missing"));
			return 0;
		}
	}

	use goah::Db::Invoicerows::Manager;
	my $rowp=goah::Db::Invoicerows::Manager->get_invoicerows( query => [ invoiceid => $_[0] ], sort_by => 'id' );
	
	unless($rowp) {
		goah::Modules->AddMessage('error',__("Couldn't find any rows for invoice id")." ".$_[0],__FILE__,__LINE__);
		return 0;
	}
	my @rows = @$rowp;

	#goah::Modules->AddMessage('debug',"Got ".scalar(@rows)." rows for invoice id ".$_[0],__FILE__,__LINE__);

	my $pdf='0';
	if($_[2]) {
		if($_[2] eq 1) {
			$pdf=2;
		} else {
			$pdf=$_[2];
		}
	}
		
	my $i=0;
	my %rowdata;
	my %productdata;
	my $pdata;
	my $vat;
	foreach my $row (@rows) {
		$rowdata{$i}{'purchase'} = goah::GoaH->FormatCurrencyNopref($row->purchase,0,0,'out',0,$pdf);
		$rowdata{$i}{'sell'} = goah::GoaH->FormatCurrencyNopref($row->sell,0,0,'out',1,$pdf);
		$rowdata{$i}{'amount'} = sprintf("%.02f",$row->amount);
		$rowdata{$i}{'rowtotal'} = goah::GoaH->FormatCurrencyNopref(($row->sell*$row->amount),0,0,'out',0,$pdf);
		$rowdata{$i}{'rowinfo'} = $row->rowinfo;
		$rowdata{$i}{'rowinfo'} =~s/€/&euro;/g;

		$pdata = goah::Modules::Productmanagement::ReadData('products',$row->productid,$uid,$settref);
		if($pdata==0) {
			goah::Modules->AddMessage('error',__("Fatal error! Can't read product information for invoice with id ".$row->productid));
			return 0;
		}
		%productdata = %$pdata;
		
		if($row->vat || $row->vat eq 0) {
			$vat=$row->vat;
			$rowdata{$i}{'vatitem'}=$row->vat."%";
		} else {
			my $vatp=goah::Modules::Systemsettings->ReadSetup($productdata{'vat'});
			my %vath;
			unless($vatp) {
				goah::Modules->AddMessage('error',__("Couldn't get VAT class from setup! VAT calculations are incorrect!"),__FILE__,__LINE__);
			} else {
				%vath=%$vatp;
			}

			goah::Modules->AddMessage('warn',__("Reading VAT from product info! There's no VAT stored for invoice row!"),__FILE__,__LINE__);
			$vat = $vath{'value'};
			$rowdata{$i}{'vatitem'}=$vath{'item'};
		}
		$rowdata{$i}{'vat'}=$vat;
		$rowdata{$i}{'rowtotal'} = goah::GoaH->FormatCurrencyNopref(($row->sell*$row->amount),0,0,'out',0,$pdf);
		$rowdata{$i}{'rowtotalvat'} = goah::GoaH->FormatCurrencyNopref(($row->sell*$row->amount),$vat,0,'out',1,$pdf);
		$rowdata{$i}{'sellvat'} = goah::GoaH->FormatCurrencyNopref($row->sell,$vat,0,'out',1,$pdf);

		$rowdata{$i}{'code'} = $productdata{'code'};
		$rowdata{$i}{'name'} = $productdata{'name'};
		$rowdata{$i}{'unit'} = $productdata{'unit'};

		$i++;
	}

	return \%rowdata;
}

#
# Function: ReadInvoicehistory
#
# Read event history for invoice
#
# Parameters:
#   
#   id - Invoice id
#
# Returns:
#
#   success -  Reference for Class::DBI results
#   fail - 0
#
sub ReadInvoicehistory {

	unless($_[0]) {
		goah::Modules->AddMessage('error',__("Can't read invoice history!")." ".__("Invoice id is missing!"));
		return 0;
	}

	use goah::Database::Invoicehistory;
	my @data = goah::Database::Invoicehistory->search_where( { invoiceid => $_[0] },{ order_by => 'time' } );

	my %hist;
	my $i=0;
	foreach my $row (@data) {

		$hist{$i}{'time'} = goah::GoaH->FormatDate($row->time);
		$hist{$i}{'action'} = $row->action;
		$hist{$i}{'startstate'} = $row->startstate;
		$hist{$i}{'endstate'} = $row->endstate;
		$hist{$i}{'info'} = $row->info;

		$i++;
	}
	return \%hist;
}

#
# Function: ReadInvoiceTotal
#
# Read and calculate total sum for invoice. Calculation includes
# total sum VAT0, total sum incl. VAT and VAT amount.
#
# Parameters:
#
#   id - Invoice id
#   pdf - If 1 return data for pdf output - DEPRECATED!
#
# Returns:
#
#   fail - 0
#   success - Hash reference with keys vat0, inclcvat and vat
#
sub ReadInvoiceTotal {

	if($_[0]=~/goah::Modules::Invoice/) {
		shift;
	}

	unless($_[0]) {
		goah::Modules->AddMessage('error',__("Can't calculate total sum for invoice! Invoice id is missing!"));
		return 0;
	}


	if($_[1]) {
		goah::Modules->AddMessage('debug',"Got deprecated parameter pdf (".$_[1].") at ReadInvoiceTotal",__FILE__,__LINE__,caller());
	}

	my $rowpointer = ReadInvoicerows($_[0],5);
	if($rowpointer == 0) {
		goah::Modules->AddMessage('error',__("Fatal error. Can't read invoice total due to faulty invoice rows!"));
		return 0;
	}
	my %rows = %$rowpointer;
	my %total;
	$total{'vat0'}=0; # price without VAT
	$total{'inclvat'}=0; # price including VAT
	$total{'vat'}=0; # basically inclvat - vat0, VAT share of total sum

	my $proddata;
	my $vat;
	foreach my $key (keys %rows) {
		$total{'vat0'}+=$rows{$key}{'rowtotal'};
		$total{'inclvat'}+=$rows{$key}{'rowtotalvat'};
		$total{'vat'}+=$rows{$key}{'rowtotalvat'}-$rows{$key}{'rowtotal'};
	}

	$total{'vat0'}=goah::GoaH->FormatCurrencyNopref($total{'vat0'},0,0,'out',0,2);
	$total{'inclvat'}=goah::GoaH->FormatCurrencyNopref($total{'inclvat'},0,0,'out',1,2);
	$total{'vat'}=goah::GoaH->FormatCurrencyNopref($total{'vat'},0,0,'out',0,2);

	return \%total;
}

#
# Function: AddEventToInvoice
#
# Add event to invoice history. Event contains mainly
# information about invoice life cycle, but it's possible
# to add other kind information as well.
#
# Parameters:
#
#   id - Id for invoice from database
#   content - Event content information
#   state - State for the invoice after event
#   action - Type of the event. If none supplied will default to 'note'
#
# Returns:
#
#   Failure - 0
#   Success - 1
#
sub AddEventToInvoice {

	unless($_[0]) {
		goah::Modules->AddMessage('error',__("Can't add event to invoice!")." ".__("Invoice id is missing!"));
		return 0;
	}

	unless($_[1]) {
		goah::Modules->AddMessage('error',__("Can't add event to invoice!")." ".__("Event content is missing!"));
	}

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my $datetime = sprintf("%04d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);

	my $invoicedata = ReadInvoices($_[0]);

	my $endstate;
	if($_[2]=~/[0-9]/) {
		$endstate = $_[2];
	} else {
		$endstate = $invoicedata->state;
	}

	my $action='note';
	if($_[3]) {
		$action = $_[3];
	}

	use goah::Database::Invoicehistory;
	goah::Database::Invoicehistory->insert({	invoiceid => $_[0],
							action => $action,
							info => $_[1],
							time => $datetime,
							startstate => $invoicedata->state,
							endstate => $endstate
						});
	
	return 1;
}

#
# Function: UpdateInvoiceinfo
#
#   Update invoice information to database. Function uses either HTTP-variables or
#   actual parameters to process the data.
#
# Parameters:
# 
#   id - Invoice id from database
#   state - Invoice state. Optional, if omitted uses HTTP variables
#
# Returns:
#
#   Success - 1
#   Failure - 0
#
sub UpdateInvoiceinfo {

	unless($_[0]) {
		goah::Modules->AddMessage('error',__("Can't update invoice information!")." ".__("Invoice id is missing!"),__FILE__,__LINE__);
		return 0;
	}

	my $q = CGI->new();

	my $invoice = ReadInvoices($_[0]);

        my $state;
        if($_[1]) {
                $state=$_[1];
        } elsif( !($q->param('state') eq '') ) {
                $state=$q->param('state');
        } else {
                goah::Modules->AddMessage('error',__("Can't update invoice information!")." ".__("Invoice state is missing!"),__FILE__,__LINE__);
                return 0;
        }

	if($invoice->state == 0 && $state == 1) {
		AddEventToInvoice($_[0],'Invoice transferred for billing.',$state,'update');
	} elsif($invoice->state == 0 && ($state == 5 || $state == 6)) {
		AddEventToInvoice($_[0],'Received payment for the invoice',$state,'closed');
	} elsif($invoice->state == 1 && ($state == 4) ) {
		AddEventToInvoice($_[0],'Invoice payment received.',$state,'closed');
	} else {
		AddEventToInvoice($_[0],'Invoice information updated.',$state,'update');
	}

	# Convert open invoice to sent, or directly paid as well
	if($invoice->state==0 && $state != 0) {
	
		# Search for next invoice number first
		my @tmp = goah::Database::Invoices->retrieve_all_sorted_by('invoicenumber');
		my $lastnumber = pop(@tmp);
		if($lastnumber->invoicenumber && $lastnumber->invoicenumber>=100) {
			$lastnumber = $lastnumber->invoicenumber;
		} else {
			$lastnumber = 50000;
		}
		$lastnumber++;
		$invoice->invoicenumber($lastnumber);

		my $refnro = CreateReferencenumber($lastnumber);
		if($refnro == 0) {
			goah::Modules->AddMessage('error',__("Can't get reference number for invoice number! Can't create invoice!"),__FILE__,__LINE__);
			return 0;
		}
		$invoice->referencenumber($refnro);

		goah::Modules->AddMessage('debug',"Payment condition: ".$q->param('payment_condition'));
		unless($q->param('payment_condition') >= 0) {
			goah::Modules->AddMessage('error',__("Payment condition isn't selected! Can't update invoice!"),__FILE__,__LINE__);
			return 0;
		}
                $invoice->payment_condition($q->param('payment_condition'));

                # Change billing date as well for today, unless user has 
                # changed the date
                if( !($q->param('created'))) {

                        # Switch created-date for today
                        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
                        my $today=sprintf("%04d-%02d-%02d",$year+1900,$mon+1,$mday);
                        $invoice->created($today);

                        goah::Modules->AddMessage('debug','Changed billing date to today',__FILE__,__LINE__);

                } else {
                        $invoice->created(goah::GoaH->FormatDate($q->param('created')));
                        goah::Modules->AddMessage('debug','Changed billing date to user setting',__FILE__,__LINE__);
                }

                my @created = split("-",$invoice->created);
                my ($dyear,$dmon,$dmday) = Add_Delta_Days($created[0],$created[1],$created[2],$invoice->payment_condition);
                my $due = sprintf("%04d-%02d-%02d",$dyear,$dmon,$dmday);
                $invoice->due($due);
	}

	# Don't change invoice state, just update date and recalc due dates
	$invoice->state($state);
	if($invoice->state==0 && $state == 0) {
		$invoice->created(goah::GoaH->FormatDate($q->param('created')));

		unless($q->param('payment_condition') >= 0) {
			goah::Modules->AddMessage('error',__("Payment condition isn't selected! Can't update invoice!"),__FILE__,__LINE__);
			return 0;
		}
		$invoice->payment_condition($q->param('payment_condition'));
	
		use Date::Calc qw(Add_Delta_Days);
		my $due;
		unless($invoice->payment_condition != '-1') {
			goah::Modules->AddMessage('error',__("Couldn't read payment condition! Can't calculate due date."));
			$due = $invoice->created();
		} else {
			if( ($invoice->state == 0) && ($state == 0) ) {
				my @created = split("-",$invoice->created);
				my ($dyear,$dmon,$dmday) = Add_Delta_Days($created[0],$created[1],$created[2],$invoice->payment_condition);
				$due = sprintf("%04d-%02d-%02d",$dyear,$dmon,$dmday);
			}
		}

		$invoice->due($due);
	}

	if($state == 5 || $state == 6) {
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
		my $received = sprintf("%04d-%02d-%02d",$year+1900,$mon+1,$mday);
		$invoice->received($received);
	}

	if($state == 4) {
		my $received;
		if($q->param('received') && !($q->param('received') eq '')) {
			$received=goah::GoaH->FormatDate($q->param('received'));
		} else {
			my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
			$received = sprintf("%04d-%02d-%02d",$year+1900,$mon+1,$mday);
		}
		$invoice->received($received);
	}

	$invoice->customerreference($q->param('customerreference'));

	$invoice->update;
	$invoice->commit;
	
	return 1;

}


# 
# Function: DeleteInvoice
#
#   Function to delete invoice information from the database. This is used only
#   when the invoice is converted back into an basket.
#
# Parameters:
#
#   id - Invoice id for removal
#
# Returns:
#
#   1 - Success
#   0 - Fail
#
sub DeleteInvoice {

	if($_[0]=~/goah::Modules::Invoice/) {
		shift;
	}

	unless($_[0]) {
		goah::Modules->AddMessage('error',__("Can't delete invoice! Id is missing!"),__FILE__,__LINE__);
		return 0;
	}

	use goah::Database::Invoices;
	use goah::Database::Invoicerows;

	my $invoice=goah::Database::Invoices->retrieve($_[0]);
	$invoice->delete;
	goah::Database::Invoices->commit;

	my @invoicerows=goah::Database::Invoicerows->search_where('invoiceid' => $_[0]);

	foreach my $row (@invoicerows) {
		$row->delete;
	}
	goah::Database::Invoicerows->commit;

	return 1;
}

1;
